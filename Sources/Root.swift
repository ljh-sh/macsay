import Foundation

enum MacsayRoot: Cmd {
    static let meta = CmdMeta(
        name: "macsay",
        desc: "macOS text-to-speech CLI — multi-language aware",
        subcmds: [
            "say": SayCmd.self,
            "voices": VoicesCmd.self,
        ],
        run: { p in
            guard let sub = p.arg(0) else {
                printCmdHelp(MacsayRoot.self)
                return
            }
            var subArgs = p
            if !subArgs.args.isEmpty {
                subArgs.args.removeFirst()
            }
            switch sub {
            case "say":
                try await SayCmd.meta.run?(subArgs)
            case "voices":
                try await VoicesCmd.meta.run?(subArgs)
            default:
                cmdError("unknown subcommand: \(sub)")
            }
        }
    )
}