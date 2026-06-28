import Foundation

/// macsay does one thing: text-to-speech. The CLI itself runs the TTS pipeline;
/// `voices` is the only subcommand (for inspecting the nsspeech engine's catalog).
///
/// We expose SayCmd's opts at the root level too, because Cmd.swift's opt parser
/// only matches opts registered on the current Cmd — there's no opt pass-through
/// to a default subcmd handler. Users get a single command surface either way.
enum MacsayRoot: Cmd {
    static let meta = CmdMeta(
        name: "macsay",
        desc: "macOS text-to-speech CLI — multi-language aware",
        opts: SayCmd.meta.opts,
        args: SayCmd.meta.args,
        subcmds: [
            "voices": VoicesCmd.self,
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