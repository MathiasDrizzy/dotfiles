// Checks for the bar, run with `swift run dotbar-tests` (exit status 1 on any failure). `swift test` needs Xcode; this
// needs only the Command Line Tools. Each area has its file and one function; add a line here for a new one.
import Foundation

await coreTests()
await weatherTests()
await mediaTests()
await frontAppTests()
await boundaryTests()
await fitTests()
await vorssaintTests()

print(failures == 0 ? "dotbar-tests: PASS" : "dotbar-tests: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
