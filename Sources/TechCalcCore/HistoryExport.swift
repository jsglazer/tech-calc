import Foundation

/// Copy as LaTeX, and the Markdown export of the history pane.
///
/// Both are pure string transforms over `HistoryEntry` values: they read no clock and no
/// filesystem, so an export is reproducible and testable line for line. The app shell's only job
/// is to put the returned string on the pasteboard or in a file.
public enum HistoryExport {

    /// One entry as a LaTeX equation: the parsed entry line, an equals sign, and the result.
    ///
    /// An entry that errored has no result to set, so its error name is carried across as text —
    /// the export shows what the calculator showed.
    public static func latex(for entry: HistoryEntry, formatter: DisplayFormatter = DisplayFormatter()) -> String {
        let left = LaTeXSerializer.latex(forInput: entry.input)
            ?? "\\text\u{7B}\(LaTeXSerializer.escaped(entry.input))\u{7D}"
        guard let result = entry.result else {
            return left + " = \\text\u{7B}\(LaTeXSerializer.escaped(entry.display))\u{7D}"
        }
        return left + " = " + LaTeXSerializer.latex(for: result.value, formatter: formatter)
    }

    /// The whole pane as a Markdown table of `$…$` equations, oldest first.
    public static func markdown(
        for entries: [HistoryEntry],
        formatter: DisplayFormatter = DisplayFormatter()
    ) -> String {
        var lines = ["| Entry | Result |", "| --- | --- |"]
        for entry in entries {
            let input = LaTeXSerializer.latex(forInput: entry.input)
                ?? LaTeXSerializer.escaped(entry.input)
            let result: String
            if let value = entry.result {
                result = LaTeXSerializer.latex(for: value.value, formatter: formatter)
            } else {
                result = "\\text\u{7B}\(LaTeXSerializer.escaped(entry.display))\u{7D}"
            }
            lines.append("| $\(input)$ | $\(result)$ |")
        }
        return lines.joined(separator: "\n")
    }
}
