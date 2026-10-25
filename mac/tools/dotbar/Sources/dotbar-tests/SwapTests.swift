// Dragging a workspace onto another swaps their windows (drag.sh and swap_workspaces in aerospace.sh).
import DotbarCore
import Foundation

func swapTests() async {
    // Three slots of 28 points (26 plus 1 on each side), as the Mac's pill lays them out.
    let slots = [
        DragSlot(id: "1", left: 0, right: 28), DragSlot(id: "2", left: 28, right: 56), DragSlot(id: "3", left: 56, right: 84),
    ]

    // Where the pointer is: the gap between two slots belongs to both (SLOT_MARGIN), and past the last one is nothing.
    check("a point inside a slot finds it", WorkspaceDrag.slot(at: 30, in: slots)?.id == "2")
    check("a point 1 point left of the first slot still finds it", WorkspaceDrag.slot(at: -1, in: slots)?.id == "1")
    check("a point 2 points left of the first slot finds nothing", WorkspaceDrag.slot(at: -2, in: slots) == nil)
    check("a point past the last slot finds nothing", WorkspaceDrag.slot(at: 86, in: slots) == nil)

    // A press that moves less than 4 points is a click on the pill it started on.
    var drag = WorkspaceDrag()
    drag.press(at: 10, slots: slots)
    check("a press on a pill arms the drag", drag.phase == .armed && drag.source?.id == "1")
    check("a 3 point move does not start a drag", drag.move(to: 13) == false && drag.phase == .armed)
    check("releasing it is a click on that pill", drag.release() == .click("1") && drag.phase == .idle)

    // A press off the pills starts nothing.
    drag.press(at: 200, slots: slots)
    check("a press off the pills stays idle", drag.phase == .idle && drag.release() == .none)

    // The fourth point starts it: the ghost is centered on the pointer, and the slot under it is the target (not the
    // source itself).
    drag.press(at: 10, slots: slots)
    check("a 4 point move starts the drag", drag.move(to: 14) == true && drag.phase == .dragging)
    check("the ghost is centered on the pointer", drag.ghostLeft == 1, "\(String(describing: drag.ghostLeft))")
    check("the source is never its own target", drag.target == nil)
    check("a later move does not start it again", drag.move(to: 40) == false)
    check("the slot under the pointer is the target", drag.target?.id == "2" && drag.ghostLeft == 27)
    _ = drag.move(to: 70)
    check("the target follows the pointer", drag.target?.id == "3")
    check(
        "releasing on a pill swaps, the ghost landing on its slot",
        drag.release() == .swap(from: "1", to: "3", landing: 56) && drag.phase == .idle && drag.target == nil)

    // Released off every pill, the ghost glides back to where it came from.
    drag.press(at: 30, slots: slots)
    _ = drag.move(to: 300)
    check("off the pills there is no target", drag.target == nil && drag.phase == .dragging)
    check("releasing there glides back to the source", drag.release() == .cancel(back: 28))
    // Back over the source, the same.
    drag.press(at: 30, slots: slots)
    _ = drag.move(to: 36)
    check("releasing on its own pill glides back", drag.release() == .cancel(back: 28))

    // The plan: windows move only while both workspaces are hidden. With the focus on one of them it parks on swap-park,
    // and afterwards follows the content that was on screen.
    let plan = WorkspaceSwap.plan(from: "1", to: "3", focused: "1", fromWindows: ["11", "12"], toWindows: ["31"])
    check(
        "a swap from the focused workspace parks, moves both ways and follows the content",
        plan
            == WorkspaceSwap.Plan(
                commands: [
                    ["workspace", "swap-park"],
                    ["move-node-to-workspace", "--window-id", "11", "3"],
                    ["move-node-to-workspace", "--window-id", "12", "3"],
                    ["move-node-to-workspace", "--window-id", "31", "1"],
                    ["workspace", "3"],
                ], focus: "3"),
        "\(plan)")
    check(
        "a swap onto the focused workspace ends on the source",
        WorkspaceSwap.plan(from: "1", to: "3", focused: "3", fromWindows: [], toWindows: ["31"]).focus == "1")
    let hidden = WorkspaceSwap.plan(from: "2", to: "3", focused: "1", fromWindows: ["21"], toWindows: [])
    check(
        "a swap of two hidden workspaces neither parks nor moves the focus",
        hidden
            == WorkspaceSwap.Plan(commands: [["move-node-to-workspace", "--window-id", "21", "3"]], focus: nil),
        "\(hidden)")
    check(
        "a workspace onto itself does nothing",
        WorkspaceSwap.plan(from: "1", to: "1", focused: "1", fromWindows: ["11"], toWindows: ["11"]).commands.isEmpty)
    check("window ids are read one per line", WorkspaceSwap.parseWindowIDs("11\n 12 \n\n") == ["11", "12"])

    // Refreshes asked for during a swap are skipped; the end of the swap repaints once.
    var gate = SwapGate()
    check("with no swap a refresh runs", gate.allowRefresh())
    gate.begin()
    check("during a swap a refresh is skipped", !gate.allowRefresh() && !gate.allowRefresh() && gate.skipped == 2)
    check("the end of the swap repaints once", gate.end() && !gate.swapping && gate.skipped == 0)
    check("a second end repaints nothing", !gate.end())

    // The whole swap through a stubbed aerospace: the commands, in order, one process at a time and each with a limit.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dotbar-swap-\(getpid())")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let log = folder.appendingPathComponent("log").path
    let stub = folder.appendingPathComponent("aerospace").path
    let script = """
        #!/bin/sh
        echo "$*" >> '\(log)'
        case "$*" in
        "list-workspaces --focused") echo 1 ;;
        "list-windows --workspace 1 --format %{window-id}") printf '11\\n12\\n' ;;
        "list-windows --workspace 3 --format %{window-id}") echo 31 ;;
        "list-windows --workspace 9 --format %{window-id}") exit 1 ;;
        "list-windows --workspace 7 --format %{window-id}") /bin/sleep 4.317 ;;
        "list-windows --workspace 5 --format %{window-id}") echo 51 ;;
        "move-node-to-workspace --window-id 51 1") exit 1 ;;
        esac
        exit 0
        """
    try? script.write(toFile: stub, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)
    func logged() -> [String] {
        ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    let result = await WorkspaceSwap.run(runner: CommandRunner(), aerospace: stub, from: "1", to: "3", timeout: 3)
    let moves = logged().filter { !$0.hasPrefix("list-") }
    check("the swap reads the focus and both workspaces' windows", logged().prefix(3).filter { $0.hasPrefix("list-") }.count == 3)
    check(
        "...then parks, moves and follows, in this order",
        moves == [
            "workspace swap-park", "move-node-to-workspace --window-id 11 3", "move-node-to-workspace --window-id 12 3",
            "move-node-to-workspace --window-id 31 1", "workspace 3",
        ], "\(moves)")
    check("...and reports where the focus ended", result == .swapped(focus: "3"), "\(result)")

    try? FileManager.default.removeItem(atPath: log)
    let failed = await WorkspaceSwap.run(runner: CommandRunner(), aerospace: stub, from: "1", to: "9", timeout: 3)
    check(
        "a workspace whose windows cannot be read moves nothing",
        failed == .unread && logged().allSatisfy { $0.hasPrefix("list-") }, "\(failed) \(logged())")

    try? FileManager.default.removeItem(atPath: log)
    let started = Date()
    let hung = await WorkspaceSwap.run(runner: CommandRunner(), aerospace: stub, from: "1", to: "7", timeout: 0.5)
    check(
        "an aerospace that hangs is cut at its limit and moves nothing",
        hung == .unread && Date().timeIntervalSince(started) < 3 && logged().allSatisfy { $0.hasPrefix("list-") },
        "\(hung)")
    check("...and leaves no process behind", await waitUntil(3) { running("sleep 4.317") == 0 })

    try? FileManager.default.removeItem(atPath: log)
    let broken = await WorkspaceSwap.run(runner: CommandRunner(), aerospace: stub, from: "1", to: "5", timeout: 3)
    let brokenMoves = logged().filter { !$0.hasPrefix("list-") }
    check("a move that fails stops the swap and says so", broken == .failed, "\(broken)")
    check(
        "...without moving more, and the focus leaves the parking workspace",
        brokenMoves == [
            "workspace swap-park", "move-node-to-workspace --window-id 11 5", "move-node-to-workspace --window-id 12 5",
            "move-node-to-workspace --window-id 51 1", "workspace 1",
        ], "\(brokenMoves)")

    try? FileManager.default.removeItem(atPath: log)
    let same = await WorkspaceSwap.run(runner: CommandRunner(), aerospace: stub, from: "3", to: "3", timeout: 3)
    check("a workspace dropped on itself runs nothing", same == .nothing && logged().isEmpty)

    try? FileManager.default.removeItem(at: folder)
}
