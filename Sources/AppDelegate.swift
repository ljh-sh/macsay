import Foundation
import AppKit

class MacsayAppDelegate: NSObject, NSApplicationDelegate {
    private let args: [String]
    private let completion: () -> Void

    init(args: [String], completion: @escaping () -> Void) {
        self.args = args
        self.completion = completion
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await runCmd(MacsayRoot.self, args)
            } catch {
                printJson(["ok": false, "error": error.localizedDescription])
            }
            completion()
            exit(0)
        }
    }
}