// The left edge's checks: the app icon map, the slide of a long app name, the Apple menu and the app menus' entries.
import DotbarCore
import Foundation

func frontAppTests() async {
    // The icon map: the same answers as sketchybar-app-font's icon_map.sh.
    check("an app gets its ligature", IconMap.glyph(for: "Ghostty") == ":ghostty:", IconMap.glyph(for: "Ghostty"))
    check("any of a case's names gets it", IconMap.glyph(for: "Chromium") == ":google_chrome:")
    check(
        "a name the map writes with a trailing * matches what starts with it",
        IconMap.glyph(for: "Adobe Photoshop 2026") == IconMap.glyph(for: "Adobe Photoshop")
            && IconMap.glyph(for: "Adobe Photoshop") != ":default:")
    check(
        "a * inside the quotes is a letter, not a wildcard",
        IconMap.glyph(for: "Foundry VTT*") == ":foundry_vtt:" && IconMap.glyph(for: "Foundry VTT 13") == ":default:")
    check("an unknown app gets the default glyph", IconMap.glyph(for: "No Such App 42") == ":default:")
    check("no app in front gets the default glyph", IconMap.glyph(for: "") == ":default:")
    check("the first case that matches wins", IconMap.glyph(for: "Hermes Agent Pro") == ":hermes_agent:")

    // Every name of the table, side by side with the shell map itself, while SketchyBar's config is still in the repo.
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "../../../../config/sketchybar/icon_map.sh"
    ).standardized.path
    if FileManager.default.fileExists(atPath: script) {
        let names = IconMap.names + ["No Such App 42", "Adobe Photoshop 2026", "Foundry VTT 13"]
        // The names go through a file: Process passes its arguments decomposed (NFD), and the shell compares bytes, so
        // "Bücher" given as an argument would not match its own case.
        let list = FileManager.default.temporaryDirectory.appendingPathComponent("dotbar-names-\(getpid())")
        try? names.joined(separator: "\n").appending("\n").write(to: list, atomically: true, encoding: .utf8)
        let shell = await CommandRunner().run(
            "/bin/bash",
            ["-c", #"source "$1"; while IFS= read -r n; do __icon_map "$n"; echo "$icon_result"; done < "$2""#, "_", script, list.path],
            timeout: 20)
        try? FileManager.default.removeItem(at: list)
        let theirs = shell.stdout.split(separator: "\n").map(String.init)
        let ours = names.map(IconMap.glyph(for:))
        let differ = zip(names, zip(ours, theirs)).filter { $0.1.0 != $0.1.1 }.map { "\($0.0): \($0.1.0) vs \($0.1.1)" }
        check(
            "all \(names.count) names map as icon_map.sh maps them",
            shell.status == 0 && theirs.count == names.count && differ.isEmpty,
            "status \(shell.status), \(theirs.count) answers, \(differ.prefix(5))")
    } else {
        print("SKIP  icon_map.sh is gone: the comparison with the shell map has nothing to compare with")
    }

    // The name's slide (app_name.sh): a name that fits sits centered; a longer one holds 1.2 s, slides left at 20 points
    // a second until its end shows (6 points further), holds, and slides back.
    check("a name that fits is centered", NameSlide.plan(textWidth: 50.4, boxWidth: 94) == .centered)
    check("a name as wide as the box fits", NameSlide.plan(textWidth: 94.6, boxWidth: 94) == .centered)
    let plan = NameSlide.plan(textWidth: 120.7, boxWidth: 94)
    check("a longer name slides by its overflow plus 6 points", plan == .slide(span: 32, seconds: 1.6), "\(plan)")
    check(
        "...holding 1.2 s before each way",
        NameSlide.steps(span: 32, seconds: 1.6)
            == [NameSlide.Step(at: 1.2, offset: -32, seconds: 1.6), NameSlide.Step(at: 4.0, offset: 0, seconds: 1.6)],
        "\(NameSlide.steps(span: 32, seconds: 1.6))")
    check(
        "the slide eases out like SketchyBar's sin curve",
        NameSlide.ease(0) == 0 && abs(NameSlide.ease(1) - 1) < 1e-9 && abs(NameSlide.ease(0.5) - 0.70710678) < 1e-6)

    // The Apple menu: sketchybarrc's apple_entry lines, in their order.
    let apple = AppleMenu.entries
    check(
        "the Apple menu has its seven entries in order",
        apple.map(\.action) == [.about, .settings, .sleep, .lock, .logout, .restart, .shutdown])
    check(
        "...with their labels",
        apple.map(\.label) == [
            "Acerca de este Mac", "Ajustes del Sistema", "Suspender", "Bloquear pantalla", "Cerrar sesión", "Reiniciar",
            "Apagar",
        ])
    check(
        "...their glyphs",
        apple.map(\.glyph) == ["\u{F02FD}", "\u{F08BB}", "\u{F0594}", "\u{F0341}", "\u{F0343}", "\u{F0709}", "\u{F0425}"])
    check(
        "...and their colors",
        apple.map(\.color) == [0x8aadf4, 0x8bd5ca, 0xc6a0f6, 0xeed49f, 0xf5a97f, 0xa6da95, 0xed8796])

    // The app's menus (appmenu.sh): the menu bar's titles without the Apple menu; a menu's items without separators, 30 at
    // most.
    check(
        "the app's menus leave out the Apple menu and untitled items",
        AppMenus.top(["Apple", "Ghostty", "File", "", nil, "Edit", "Help"]) == ["Ghostty", "File", "Edit", "Help"])
    check(
        "a menu's items leave out separators",
        AppMenus.items(["New Window", nil, "", "missing value", "Close"]) == ["New Window", "Close"])
    check("a long menu shows its first 30 items", AppMenus.items((1...45).map { "Item \($0)" }).count == 30)
}
