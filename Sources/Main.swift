import Foundation
import AppKit

var gAppDelegate: MacsayAppDelegate?

@main
struct Entry {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.isEmpty || args.contains("--help") || args.contains("-h") {
            do {
                try await runCmd(MacsayRoot.self, args)
            } catch {
                printJson(["ok": false, "error": error.localizedDescription])
                exit(1)
            }
            return
        }

        await withCheckedContinuation { continuation in
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            gAppDelegate = MacsayAppDelegate(args: args) {
                continuation.resume()
            }
            app.delegate = gAppDelegate
            app.run()
        }
    }
}