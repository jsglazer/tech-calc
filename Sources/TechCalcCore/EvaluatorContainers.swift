import Foundation

/// The list and matrix half of the evaluator.
///
/// It is split out from `Evaluator` for readability only: there is still one dispatch point on
/// `FunctionID`, one value type crossing the evaluator, and one 1-based/0-based boundary per
/// container (the accessors on `TIList` and `TIMatrix`). Nothing here computes a name from a
/// string — every function is reached by its catalog id.
extension Evaluator {

    // MARK: - Container-valued expressions

    func listValue(_ value: TIValue) throws -> TIList {
        guard case .list(let list) = value else { throw TIError.dataType }
        return list
    }

    func matrixValue(_ value: TIValue) throws -> TIMatrix {
        guard case .matrix(let matrix) = value else { throw TIError.dataType }
        return matrix
    }

    /// `{1,2,3}` and `[[1,2][3,4]]`: the elements must be numbers, so a nested container is a
    /// data-type error rather than a silently flattened one.
    mutating func evaluateListLiteral(_ elements: [Expression]) throws -> TIValue {
        var values: [Complex] = []
        for element in elements {
            values.append(try evaluate(element).asComplex)
        }
        guard values.count <= TILimits.maxListLength else { throw TIError.invalidDimension }
        return .list(TIList(values))
    }

    mutating func evaluateMatrixLiteral(_ rows: [[Expression]]) throws -> TIValue {
        var grid: [[Complex]] = []
        for row in rows {
            var values: [Complex] = []
            for element in row {
                values.append(try evaluate(element).asComplex)
            }
            grid.append(values)
        }
        return .matrix(try MatrixMath.matrix(from: grid))
    }

    /// `L1(3)` and `[A](2,3)`. The subscripts are TI-numbered; the accessors on `TIList` and
    /// `TIMatrix` are the only place they become Swift indices.
    mutating func evaluateElement(_ base: Expression, _ subscripts: [Expression]) throws -> TIValue {
        let container = try evaluate(base)
        var indices: [Int] = []
        for expression in subscripts {
            indices.append(try evaluate(expression).asInteger)
        }
        switch container {
        case .list(let list):
            guard indices.count == 1 else { throw TIError.invalidDimension }
            return .number(try list[tiIndex: indices[0]])
        case .matrix(let matrix):
            guard indices.count == 2 else { throw TIError.invalidDimension }
            return .number(try matrix[tiRow: indices[0], tiColumn: indices[1]])
        case .real, .complex, .string:
            throw TIError.dataType
        }
    }

    // MARK: - Stores

    mutating func store(_ value: TIValue, into target: StoreTarget) throws {
        switch target {
        case .variable(let name):
            try context.setValue(try value.asComplex, for: name)

        case .randomSeed:
            random.reseed(UInt64(bitPattern: Int64(try value.asInteger)))

        case .list(let name):
            context.lists[name] = try listValue(value)

        case .matrix(let name):
            context.matrices[name] = try matrixValue(value)

        case .listElement(let name, let indexExpression):
            let index = try evaluate(indexExpression).asInteger
            var list = context.list(name)
            // Storing one past the end appends, as the TI's list editor does.
            if index == list.count + 1 {
                try list.resize(to: index)
            }
            try list.set(tiIndex: index, to: try value.asComplex)
            context.lists[name] = list

        case .matrixElement(let name, let rowExpression, let columnExpression):
            let row = try evaluate(rowExpression).asInteger
            let column = try evaluate(columnExpression).asInteger
            var matrix = try context.matrix(name)
            try matrix.set(tiRow: row, tiColumn: column, to: try value.asComplex)
            context.matrices[name] = matrix

        case .listDimension(let name):
            var list = context.list(name)
            try list.resize(to: try value.asInteger)
            context.lists[name] = list

        case .matrixDimension(let name):
            let dimensions = try listValue(value)
            guard dimensions.count == 2 else { throw TIError.invalidDimension }
            let rows = try TIValue.number(dimensions.values[0]).asInteger
            let columns = try TIValue.number(dimensions.values[1]).asInteger
            context.matrices[name] = try reshaped(context.matrices[name], rows: rows, columns: columns)
        }
    }

    /// `{r,c}→dim([A])`: keeps the elements in row-major order, padding with zeros and
    /// truncating as needed, exactly as resizing a list does.
    private func reshaped(_ matrix: TIMatrix?, rows: Int, columns: Int) throws -> TIMatrix {
        var values = [Complex](repeating: .zero, count: Swift.max(0, rows * columns))
        if let matrix {
            for row in 0..<Swift.min(rows, matrix.rows) {
                for column in 0..<Swift.min(columns, matrix.columns) {
                    values[row * columns + column] = matrix.values[row * matrix.columns + column]
                }
            }
        }
        return try TIMatrix(rows: rows, columns: columns, values: values)
    }

    // MARK: - Element-wise broadcasting

    /// Negation reaches lists and matrices as well as numbers, so it cannot go through
    /// `asComplex` alone.
    func negated(_ value: TIValue) throws -> TIValue {
        switch value {
        case .real, .complex: .number(-(try value.asComplex))
        case .list(let list): .list(TIList(list.values.map { -$0 }))
        case .matrix(let matrix): .matrix(try MatrixMath.scale(matrix, by: Complex(-1)))
        case .string: throw TIError.dataType
        }
    }

    /// Maps a scalar function over a list argument: `sin(L1)` is a list of sines, and
    /// `gcd(L1,L2)` pairs the lists element by element.
    ///
    /// Returns `nil` when no argument is a list, so the scalar path is untouched.
    func broadcastOverLists(
        _ id: FunctionID,
        _ values: [TIValue],
        _ scalar: ([TIValue]) throws -> TIValue
    ) throws -> TIValue? {
        let lengths = values.compactMap { value -> Int? in
            if case .list(let list) = value { return list.count }
            return nil
        }
        guard let length = lengths.first else { return nil }
        guard lengths.allSatisfy({ $0 == length }) else { throw TIError.dimensionMismatch }

        var results: [Complex] = []
        results.reserveCapacity(length)
        for index in 0..<length {
            let slice = try values.map { value -> TIValue in
                guard case .list(let list) = value else { return value }
                return .number(try list[tiIndex: index + 1])
            }
            results.append(try scalar(slice).asComplex)
        }
        return .list(TIList(results))
    }

    /// Arithmetic where at least one side is a container. Returns `nil` for two scalars.
    func applyToContainers(_ op: BinaryOperator, _ lhs: TIValue, _ rhs: TIValue) throws -> TIValue? {
        switch (lhs, rhs) {
        case (.list, _), (_, .list):
            return try applyToLists(op, lhs, rhs)
        case (.matrix, _), (_, .matrix):
            return try applyToMatrices(op, lhs, rhs)
        default:
            return nil
        }
    }

    private func applyToLists(_ op: BinaryOperator, _ lhs: TIValue, _ rhs: TIValue) throws -> TIValue {
        guard op != .equal, op != .notEqual else { throw TIError.dataType }
        let left = try elements(of: lhs, matching: rhs)
        let right = try elements(of: rhs, matching: lhs)
        guard left.count == right.count else { throw TIError.dimensionMismatch }
        var results: [Complex] = []
        results.reserveCapacity(left.count)
        for index in 0..<left.count {
            results.append(try scalarOperation(op, left[index], right[index]))
        }
        return .list(TIList(results))
    }

    /// A list stays itself; a scalar is repeated to the other side's length. A matrix mixed with
    /// a list is `ERR:DATA TYPE`, as on the TI.
    private func elements(of value: TIValue, matching other: TIValue) throws -> [Complex] {
        switch value {
        case .list(let list):
            return list.values
        case .real, .complex:
            guard case .list(let otherList) = other else { throw TIError.dataType }
            return Array(repeating: try value.asComplex, count: otherList.count)
        case .matrix, .string:
            throw TIError.dataType
        }
    }

    private func applyToMatrices(_ op: BinaryOperator, _ lhs: TIValue, _ rhs: TIValue) throws -> TIValue {
        switch (lhs, rhs, op) {
        case (.matrix(let a), .matrix(let b), .add):
            return .matrix(try MatrixMath.add(a, b))
        case (.matrix(let a), .matrix(let b), .subtract):
            return .matrix(try MatrixMath.subtract(a, b))
        case (.matrix(let a), .matrix(let b), .multiply):
            return .matrix(try MatrixMath.multiply(a, b))
        case (.matrix(let a), _, .multiply):
            return .matrix(try MatrixMath.scale(a, by: try rhs.asComplex))
        case (_, .matrix(let b), .multiply):
            return .matrix(try MatrixMath.scale(b, by: try lhs.asComplex))
        case (.matrix(let a), _, .divide):
            let divisor = try rhs.asComplex
            guard divisor != .zero else { throw TIError.divideByZero }
            return .matrix(try MatrixMath.scale(a, by: try Complex.one / divisor))
        case (.matrix(let a), _, .power):
            return .matrix(try MatrixMath.power(a, try rhs.asInteger))
        default:
            // Matrix ± scalar, and every relational comparison, are data-type errors on the TI.
            throw TIError.dataType
        }
    }

    private func scalarOperation(_ op: BinaryOperator, _ a: Complex, _ b: Complex) throws -> Complex {
        switch op {
        case .add: a + b
        case .subtract: a - b
        case .multiply: a * b
        case .divide: try a / b
        case .power: try Complex.pow(a, b)
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
            try comparisonValue(op, a, b)
        }
    }

    private func comparisonValue(_ op: BinaryOperator, _ a: Complex, _ b: Complex) throws -> Complex {
        guard a.isReal, b.isReal else { throw TIError.dataType }
        let result: Bool
        switch op {
        case .less: result = a.re < b.re
        case .lessEqual: result = a.re <= b.re
        case .greater: result = a.re > b.re
        case .greaterEqual: result = a.re >= b.re
        default: throw TIError.syntax
        }
        return Complex(result ? 1 : 0)
    }

    // MARK: - The LIST and MATRX function menus

    /// The container functions that take ordinary evaluated arguments. Returns `nil` when `id`
    /// is not one of them, so the scalar switch stays the single home of scalar functions.
    func applyContainerFunction(_ id: FunctionID, _ values: [TIValue]) throws -> TIValue? {
        switch id {
        // MARK: shape
        case .dimension:
            switch values[0] {
            case .list(let list): return .real(Double(list.count))
            case .matrix(let matrix):
                return .list(TIList(reals: [Double(matrix.rows), Double(matrix.columns)]))
            default: throw TIError.dataType
            }

        // MARK: LIST MATH
        case .listSum, .listProduct:
            let list = try listValue(values[0])
            let start = values.count > 1 ? try values[1].asInteger : nil
            let end = values.count > 2 ? try values[2].asInteger : nil
            let window = try ListMath.window(list, start: start, end: end)
            return .number(id == .listSum ? ListMath.sum(window) : ListMath.product(window))
        case .listMean:
            return .number(try ListMath.mean(try listValue(values[0]).values))
        case .listMedian:
            return .real(try ListMath.median(try listValue(values[0]).values))
        case .listStandardDeviation:
            return .real(try ListMath.standardDeviation(try listValue(values[0]).values))
        case .listVariance:
            return .real(try ListMath.variance(try listValue(values[0]).values))

        // MARK: min( and max( — a reduction over one list, or element-wise over two
        case .minimum, .maximum:
            return try extremum(id, values)

        // MARK: LIST OPS
        case .cumulativeSum:
            return .list(ListMath.cumulativeSum(try listValue(values[0])))
        case .listDifference:
            return .list(try ListMath.differences(try listValue(values[0])))
        case .augment:
            if case .matrix(let a) = values[0] {
                return .matrix(try MatrixMath.augment(a, try matrixValue(values[1])))
            }
            return .list(try ListMath.augment(try listValue(values[0]), try listValue(values[1])))

        // MARK: MATRX MATH
        case .determinant:
            return .number(try MatrixMath.determinant(try matrixValue(values[0])))
        case .transpose:
            return .matrix(try MatrixMath.transpose(try matrixValue(values[0])))
        case .identityMatrix:
            return .matrix(try MatrixMath.identity(size: try values[0].asInteger))
        case .randomMatrix:
            return .matrix(try randomMatrix(rows: try values[0].asInteger, columns: try values[1].asInteger))
        case .rowEchelon:
            return .matrix(try MatrixMath.rowEchelonForm(try matrixValue(values[0])))
        case .reducedRowEchelon:
            return .matrix(try MatrixMath.reducedRowEchelonForm(try matrixValue(values[0])))
        case .rowSwap:
            return .matrix(try MatrixMath.swappingRows(
                try matrixValue(values[0]), try values[1].asInteger, try values[2].asInteger))
        case .rowAdd:
            return .matrix(try MatrixMath.addingRow(
                try matrixValue(values[0]), from: try values[1].asInteger, to: try values[2].asInteger))
        case .rowScale:
            return .matrix(try MatrixMath.scalingRow(
                try matrixValue(values[1]), try values[2].asInteger, by: try values[0].asComplex))
        case .rowScaleAdd:
            return .matrix(try MatrixMath.transformingRow(
                try matrixValue(values[1]),
                from: try values[2].asInteger,
                to: try values[3].asInteger,
                factor: try values[0].asComplex))

        // MARK: the powers and roots that mean something different for a matrix
        case .reciprocal, .square, .cube:
            guard case .matrix(let matrix) = values[0] else { return nil }
            let exponent = id == .reciprocal ? -1 : (id == .square ? 2 : 3)
            return .matrix(try MatrixMath.power(matrix, exponent))
        case .absoluteValue:
            guard case .list(let list) = values[0] else { return nil }
            return .list(TIList(reals: list.values.map(\.magnitude)))

        default:
            return nil
        }
    }

    private func extremum(_ id: FunctionID, _ values: [TIValue]) throws -> TIValue? {
        let wantsMinimum = id == .minimum
        if values.count == 1 {
            let elements = try listValue(values[0]).values
            return .real(wantsMinimum ? try ListMath.minimum(elements) : try ListMath.maximum(elements))
        }
        guard values.contains(where: { if case .list = $0 { return true } else { return false } }) else {
            // Two scalars: the ordinary MATH NUM behaviour, handled on the scalar path.
            return nil
        }
        let left = try listValue(values[0].isNumber ? .list(TIList(repeating: try values[0].asComplex,
                                                                   count: try listValue(values[1]).count))
                                                   : values[0])
        let right = try listValue(values[1].isNumber ? .list(TIList(repeating: try values[1].asComplex,
                                                                    count: left.count))
                                                    : values[1])
        guard left.count == right.count else { throw TIError.dimensionMismatch }
        let leftReals = try ListMath.realValues(left.values)
        let rightReals = try ListMath.realValues(right.values)
        let paired = zip(leftReals, rightReals).map { wantsMinimum ? Swift.min($0, $1) : Swift.max($0, $1) }
        return .list(TIList(reals: paired))
    }

    /// `randM(` draws integers in -9...9, the TI's range, from the injected generator — never
    /// from an unseeded source.
    private func randomMatrix(rows: Int, columns: Int) throws -> TIMatrix {
        guard rows >= 1, columns >= 1,
              rows <= TILimits.maxMatrixDimension, columns <= TILimits.maxMatrixDimension else {
            throw TIError.invalidDimension
        }
        var values: [Complex] = []
        values.reserveCapacity(rows * columns)
        for _ in 0..<(rows * columns) {
            values.append(Complex(Double(try random.nextInteger(
                lower: -TILimits.randomMatrixMagnitude,
                upper: TILimits.randomMatrixMagnitude))))
        }
        return try TIMatrix(rows: rows, columns: columns, values: values)
    }

    // MARK: - Commands that name a container rather than take its value

    /// `SortA(`, `SortD(`, `Fill(`, `seq(`, `List▸matr(` and `Matr▸list(`. They receive their
    /// arguments unevaluated because they need the container's *name*: sorting `L1` must write
    /// back into `L1`, not into a copy of its contents.
    mutating func evaluateContainerCommand(_ id: FunctionID, _ arguments: [Expression]) throws -> TIValue? {
        switch id {
        case .sortAscending, .sortDescending:
            guard case .listVariable(let name) = arguments[0] else { throw TIError.dataType }
            context.lists[name] = try ListMath.sorted(context.list(name), ascending: id == .sortAscending)
            return .done

        case .fill:
            let value = try evaluate(arguments[0]).asComplex
            switch arguments[1] {
            case .listVariable(let name):
                let list = context.list(name)
                context.lists[name] = TIList(repeating: value, count: list.count)
            case .matrixVariable(let name):
                let matrix = try context.matrix(name)
                context.matrices[name] = try TIMatrix(
                    rows: matrix.rows,
                    columns: matrix.columns,
                    values: Array(repeating: value, count: matrix.rows * matrix.columns))
            default:
                throw TIError.dataType
            }
            return .done

        case .sequence:
            return .list(try sequence(arguments))

        case .listToMatrix:
            // `List▸matr(list, ..., [A])`: the lists become the matrix's columns.
            guard case .matrixVariable(let name) = arguments[arguments.count - 1] else {
                throw TIError.dataType
            }
            var lists: [TIList] = []
            for expression in arguments.dropLast() {
                lists.append(try listValue(try evaluate(expression)))
            }
            context.matrices[name] = try ListMath.matrix(fromColumns: lists)
            return .done

        case .matrixToList:
            // `Matr▸list([A], L1, ...)`: each column becomes one list.
            let matrix = try matrixValue(try evaluate(arguments[0]))
            let columns = ListMath.columns(of: matrix)
            let targets = Array(arguments.dropFirst())
            guard targets.count <= columns.count else { throw TIError.dimensionMismatch }
            for (offset, expression) in targets.enumerated() {
                guard case .listVariable(let name) = expression else { throw TIError.dataType }
                context.lists[name] = columns[offset]
            }
            return .done

        default:
            return nil
        }
    }

    /// `seq(expression, variable, start, end[, step])`, evaluated over a bounded index so a
    /// pathological step cannot spin.
    private mutating func sequence(_ arguments: [Expression]) throws -> TIList {
        guard case .variable(let name) = arguments[1] else { throw TIError.syntax }
        let start = try evaluate(arguments[2]).asReal
        let end = try evaluate(arguments[3]).asReal
        let step = arguments.count == 5 ? try evaluate(arguments[4]).asReal : 1
        guard step != 0, step.isFinite, start.isFinite, end.isFinite else { throw TIError.domain }

        let span = (end - start) / step
        guard span >= 0 else { throw TIError.invalidDimension }
        let count = Int(span.rounded(.down)) + 1
        guard count <= TILimits.maxListLength else { throw TIError.invalidDimension }

        var values: [Complex] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            var local = self
            try local.context.setValue(Complex(start + Double(index) * step), for: name)
            values.append(try local.evaluate(arguments[0]).asComplex)
        }
        return TIList(values)
    }
}
