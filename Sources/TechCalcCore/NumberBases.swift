import Foundation

/// Number-base entry, base display, and the bitwise operators.
///
/// This part of the concept is beyond TI-84 Plus CE parity — the CE has no BASE menu — so the
/// post-M4 decisions (D22) fix its shape rather than hardware doing so. Two consequences are
/// visible here:
///
///   * the bitwise operators are named functions (`bitAnd(` and friends), entirely separate from
///     the boolean `and`/`or`/`xor`/`not` the TEST LOGIC menu already declares, so nothing that
///     was already a valid expression changes meaning;
///   * the operators carry no hidden base mode. A value is a number; a base is a way of *writing*
///     one, chosen by an entry prefix or a display conversion. `bitAnd(2,3)` is 2 whatever base
///     the answer is being shown in.
public enum NumberBases {

    /// The prefix an entered literal carries, and the prefix a converted answer is written with.
    /// Declared once here: the tokenizer reads them and so does the renderer.
    public static let binaryPrefix = "0b"
    public static let hexadecimalPrefix = "0h"
    /// Octal has a display conversion but no entry prefix, which is D22 as written.
    public static let octalPrefix = "0o"

    /// The width the bitwise operators and the base renderer work in. A value outside the signed
    /// range of this width is `ERR:DOMAIN` rather than a silently truncated answer.
    public static let bitWidth = 32

    static let upperBound = Double(Int64(1) << (bitWidth - 1))          // 2^31
    static let lowerBound = -Double(Int64(1) << (bitWidth - 1))         // -2^31

    /// A real value as the 32-bit integer the bitwise and base operations act on.
    ///
    /// This is the single conversion point into integer-land, so "what counts as representable"
    /// is one rule rather than one per operation.
    public static func integer(_ value: Double) throws -> Int64 {
        guard value.isFinite, value == value.rounded() else { throw TIError.domain }
        guard value >= lowerBound, value < upperBound else { throw TIError.domain }
        return Int64(value)
    }

    /// The unsigned two's-complement pattern of a value, which is what a base other than ten
    /// displays. `-1` shows as all ones, exactly as on a machine of this width.
    static func pattern(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: value) & ((UInt64(1) << UInt64(bitWidth)) - 1)
    }

    // MARK: - Rendering

    /// The prefix and radix a display conversion asks for, or nil when the conversion is not a
    /// base conversion. The one place a base conversion id is tied to how it is written.
    static func base(for id: FunctionID) -> (prefix: String, radix: Int)? {
        switch id {
        case .toBinary: (binaryPrefix, 2)
        case .toHexadecimal: (hexadecimalPrefix, 16)
        case .toOctal: (octalPrefix, 8)
        default: nil
        }
    }

    public static func isBaseConversion(_ id: FunctionID) -> Bool { base(for: id) != nil }

    /// A value written in the base a conversion names, or nil when the conversion is not a base
    /// conversion or the value cannot be written in one.
    ///
    /// The evaluator rejects an out-of-range operand before the answer is ever formatted, so the
    /// nil path here is a formatter fallback rather than the way an error is reported.
    public static func text(for value: TIValue, conversion id: FunctionID) -> String? {
        guard let base = base(for: id),
              case .real(let real) = value,
              let integer = try? self.integer(real) else { return nil }
        let digits = String(pattern(integer), radix: base.radix, uppercase: true)
        return base.prefix + digits
    }

    // MARK: - Entry

    /// Scans a based literal — `0b1101`, `0hFF` — returning its value and how many characters it
    /// spans, or nil when the text at `index` is not one.
    ///
    /// A prefix with no digits after it is *not* a literal: `0b` on its own stays the number zero
    /// followed by the variable `b`, so nothing that already parsed changes meaning.
    static func scanLiteral(_ characters: [Character], at index: Int) -> (value: Double, length: Int)? {
        for (prefix, radix) in [(binaryPrefix, 2), (hexadecimalPrefix, 16)] {
            let prefixCharacters = Array(prefix)
            guard index + prefixCharacters.count <= characters.count else { continue }
            guard Array(characters[index..<(index + prefixCharacters.count)]) == prefixCharacters else { continue }

            var length = prefixCharacters.count
            var digits = ""
            while index + length < characters.count,
                  let digit = characters[index + length].hexDigitValue, digit < radix {
                digits.append(characters[index + length])
                length += 1
            }
            guard !digits.isEmpty, let magnitude = UInt64(digits, radix: radix) else { continue }
            // Written patterns are unsigned; a full-width pattern reads back as its signed value,
            // so `0hFFFFFFFF` and `⁻1` are the same number.
            guard magnitude < (UInt64(1) << UInt64(bitWidth)) else { continue }
            let signed = magnitude >= (UInt64(1) << UInt64(bitWidth - 1))
                ? Int64(bitPattern: magnitude &- (UInt64(1) << UInt64(bitWidth)))
                : Int64(magnitude)
            return (Double(signed), length)
        }
        return nil
    }

    // MARK: - Bitwise operators

    public static func and(_ a: Double, _ b: Double) throws -> Double {
        Double(try integer(a) & (try integer(b)))
    }

    public static func or(_ a: Double, _ b: Double) throws -> Double {
        Double(try integer(a) | (try integer(b)))
    }

    public static func xor(_ a: Double, _ b: Double) throws -> Double {
        Double(try integer(a) ^ (try integer(b)))
    }

    /// Two's-complement inversion: every bit flipped, which is `-x - 1`.
    public static func not(_ a: Double) throws -> Double {
        Double(~(try integer(a)))
    }
}
