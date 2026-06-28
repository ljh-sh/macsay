import Foundation

/// MLX-Audio backed TTS engine. Spawns a Python helper that uses `mlx_audio`
/// to run Qwen3-TTS models on Apple Silicon.
///
/// Three Qwen3-TTS modes are supported:
/// - VoiceDesign: text-to-voice via prompt (e.g. "female, British narrator")
/// - CustomVoice: pre-defined voices like "Ryan" / "Aiden"
/// - Base: 3-second voice clone from a reference audio + transcript
///
/// Models are downloaded from the MLX Community on Hugging Face. The CLI
/// shells out to Python rather than linking MLX directly, keeping the macsay
/// binary small and avoiding an MLX runtime dependency.
enum MlxEngine {
    struct Config {
        var model: String = "models/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
        var voiceDesign: String?
        var speaker: String = "Ryan"
        var instruct: String?
        var refAudio: String?
        var refText: String?
        var lang: String = "English"
        var audioFormat: String = "wav"
        var joinAudio: Bool = true
        var pythonPath: String = "/opt/homebrew/bin/python3"
        var venvPath: String = "./qwen3-tts/venv"
        var verbose: Bool = false
    }

    enum MlxError: Error {
        case pythonNotFound(String)
        case venvNotFound(String)
        case modelNotFound(String)
        case synthesisFailed(String)
    }

    /// Run TTS via the bundled Python helper. Returns the path of the generated
    /// audio file (typically `output_dir/<name>.<audioFormat>`).
    static func synthesize(text: String, config: Config, outputDir: String) throws -> String {
        // Sanity checks up front — fail fast with a clean error.
        guard FileManager.default.isExecutableFile(atPath: config.pythonPath) else {
            throw MlxError.pythonNotFound(config.pythonPath)
        }
        let venvPython = locateVenvPython(fallback: config.venvPath)
        guard FileManager.default.isExecutableFile(atPath: venvPython) else {
            throw MlxError.venvNotFound(venvPython)
        }
        guard FileManager.default.fileExists(atPath: config.model) else {
            throw MlxError.modelNotFound(config.model)
        }

        // Locate the bundled helper script.
        let helperPath = locateHelper()
        guard FileManager.default.fileExists(atPath: helperPath) else {
            throw MlxError.synthesisFailed("helper not found: \(helperPath)")
        }

        var args = [helperPath, "--text", text, "--model", config.model, "--output", outputDir]
        if let d = config.voiceDesign { args += ["--voice-design", d] }
        if let i = config.instruct { args += ["--instruct", i] }
        args += ["--speaker", config.speaker]
        if let a = config.refAudio { args += ["--ref-audio", a] }
        if let t = config.refText { args += ["--ref-text", t] }
        args += ["--lang", config.lang, "--format", config.audioFormat]
        if config.joinAudio { args += ["--join"] }
        if config.verbose { args += ["--verbose"] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: venvPython)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw MlxError.synthesisFailed(errMsg)
        }

        return "\(outputDir)/out.\(config.audioFormat)"
    }

    /// Find a usable venv Python: try the configured path first, then probe
    /// common locations relative to the current working directory. Returns the
    /// configured path if nothing else is found (caller will then surface a
    /// clean `venvNotFound` error).
    private static func locateVenvPython(fallback: String) -> String {
        let fm = FileManager.default
        let candidates: [String] = [
            fallback,
            "\(fallback)/bin/python3",
            FileManager.default.currentDirectoryPath + "/qwen3-tts/venv/bin/python3",
            FileManager.default.currentDirectoryPath + "/venv/bin/python3",
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) {
            return c
        }
        return "\(fallback)/bin/python3"
    }

    private static func locateHelper() -> String {
        // Look for the helper relative to the executable first, then the cwd.
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            cwd + "/qwen3-tts/qwen3_tts_helper.py",
            cwd + "/qwen3_tts_helper.py",
            cwd + "/Resources/qwen3_tts_helper.py",
            "./qwen3_tts_helper.py",
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) { return c }
        }
        return candidates[0] // Will be reported as missing above
    }
}