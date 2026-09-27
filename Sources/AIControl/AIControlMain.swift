import AIControlCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Executable entry point. All behavior lives in `AIControlCore` so it can be
/// imported by the test target, which cannot import a `@main` executable target.
@main
enum AIControlMain {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        #if os(macOS)
        if arguments.count == 2, arguments[0] == "render-screenshots" { exit(renderScreenshots(to: arguments[1])) }
        #endif
        exit(runClaudeLogins(arguments: arguments))
    }
}
