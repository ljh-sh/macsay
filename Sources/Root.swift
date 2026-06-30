import Foundation

/// macsay does one thing: text-to-speech. The CLI itself runs the TTS pipeline;
/// `voices` and `pull` are auxiliary subcommands (no speech synthesis).
enum MacsayRoot: Cmd {
    static let meta = CmdMeta(
        name: "macsay",
        desc: "macOS text-to-speech CLI — multi-language aware",
        opts: SayCmd.meta.opts,
        args: SayCmd.meta.args,
        subcmds: [
            "voices": VoicesCmd.self,
            "pull": PullCmd.self,
        ],
        run: { p in
            // Dispatch on first arg if it is a registered subcmd.
            if let sub = p.arg(0) {
                switch sub {
                case "voices":
                    var subArgs = p
                    if !subArgs.args.isEmpty {
                        subArgs.args.removeFirst()
                    }
                    try await VoicesCmd.meta.run?(subArgs)
                    return
                case "pull":
                    var subArgs = p
                    if !subArgs.args.isEmpty {
                        subArgs.args.removeFirst()
                    }
                    try await PullCmd.meta.run?(subArgs)
                    return
                case "--help", "-h":
                    printCmdHelp(MacsayRoot.self)
                    return
                default:
                    // Treat all args as text for the default TTS command.
                    break
                }
            }
            // No subcommand → run the default TTS pipeline.
            try await SayCmd.meta.run?(p)
        }
    )
}