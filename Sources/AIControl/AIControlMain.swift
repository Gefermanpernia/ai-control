import AIControlCore
import Darwin

/// Executable entry point. All behavior lives in `AIControlCore` so it can be
/// imported by the test target, which cannot import a `@main` executable target.
@main
enum AIControlMain {
    @MainActor
    static func main() {
        exit(runClaudeLogins(arguments: Array(CommandLine.arguments.dropFirst())))
    }
}
