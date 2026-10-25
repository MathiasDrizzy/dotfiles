/// App name -> sketchybar-app-font ligature, the map SketchyBar's front app used (icon_map.sh): its cases are tried in
/// order and the first one whose name matches wins, ":default:" when none does. The table is IconMapTable.swift, made from
/// icon_map.sh: between START-OF-ICON-MAP and END-OF-ICON-MAP, each case line `"a" | "b"*)` becomes one line with the
/// next line's icon_result, then "=a" and "^b", separated by tabs. The checks compare every name with the shell map.
public enum IconMap {
    struct Rule {
        let glyph: String
        let exact: Set<String>
        let prefixes: [String]
    }

    static let rules: [Rule] = table.split(separator: "\n").map { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let patterns = fields.dropFirst()
        return Rule(
            glyph: fields[0],
            exact: Set(patterns.filter { $0.hasPrefix("=") }.map { String($0.dropFirst()) }),
            prefixes: patterns.filter { $0.hasPrefix("^") }.map { String($0.dropFirst()) })
    }

    /// The ligature sketchybar-app-font draws for an app, by the name the system shows for it.
    public static func glyph(for app: String) -> String {
        rules.first { $0.exact.contains(app) || $0.prefixes.contains(where: app.hasPrefix) }?.glyph ?? ":default:"
    }

    /// Every name the map knows, in its order: the checks compare each one with icon_map.sh itself.
    public static var names: [String] {
        table.split(separator: "\n").flatMap { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).dropFirst().map { String($0.dropFirst()) }
        }
    }
}
