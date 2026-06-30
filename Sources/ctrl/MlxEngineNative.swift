// MlxEngineNative.swift
//
// Swift-native MLX engine backed by `Blaizzy/mlx-audio-swift`.
//
// This is the default MLX engine for macsay v0.4+. It loads Qwen3-TTS models
// directly in-process — no Python helper, no separate venv.
//
// Requires: mlx.metallib colocated with the macsay binary (build script
// generates it from mlx-swift/Source/Cmlx/mlx-generated/metal/*.metal).

import Foundation
import MLX
import MLXAudioCore
import MLXAudioTTS

enum MlxEngineNative {
    struct Config {
        /// Hugging Face repo id (e.g. "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit")
        /// or local path to a model directory.
        var model: String = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
        /// For VoiceDesign mode: prompt like "female, British narrator".
        var voiceDesign: String?
        /// For CustomVoice mode: speaker name (e.g. "Ryan", "Aiden").
        var speaker: String = "Ryan"
        /// Optional style instruction for CustomVoice.
        var instruct: String?
        /// For Base mode: path to reference audio (3-second voice clone).
        var refAudio: String?
        /// For Base mode: transcript of reference audio.
        var refText: String?
        /// Target language (e.g. "English", "Chinese").
        var lang: String = "English"
    }

    enum MlxError: Error {
        case modelNotFound(String)
        case synthesisFailed(String)
        case pullFailed(String)
    }

    /// Run TTS in-process. Returns the WAV file path.
    static func synthesize(text: String, config: Config, outputURL: URL) async throws -> String {
        let model: SpeechGenerationModel
        do {
            model = try await TTS.loadModel(modelRepo: config.model)
        } catch {
            throw MlxError.modelNotFound("\(config.model): \(error.localizedDescription)")
        }

        var refAudio: MLXArray? = nil
        if let path = config.refAudio {
            let url = URL(fileURLWithPath: path)
            let (_, samples) = try loadAudioArray(from: url)
            refAudio = samples.reshaped([1, -1])
        }

        let audio: MLXArray
        do {
            audio = try await model.generate(
                text: text,
                voice: config.voiceDesign ?? config.speaker,
                refAudio: refAudio,
                refText: config.refText,
                language: config.lang,
                generationParameters: model.defaultGenerationParameters
            )
        } catch {
            throw MlxError.synthesisFailed(error.localizedDescription)
        }

        do {
            let samples = audio.asArray(Float.self)
            try AudioUtils.writeWavFile(
                samples: samples,
                sampleRate: Double(model.sampleRate),
                fileURL: outputURL
            )
        } catch {
            throw MlxError.synthesisFailed("write failed: \(error.localizedDescription)")
        }

        return outputURL.path
    }

    /// Pull an MLX-community model from Hugging Face into the HF Hub cache.
/// Auto-detects which tool is available (hf / uvx / x-cmd uvx) and uses
/// it to download. Sets HF_ENDPOINT (mirror) automatically and forwards
/// any http_proxy / https_proxy from the parent environment.
///
/// NOTE: We deliberately do NOT pass `--local-dir` — we let the download tool
/// write to the standard HF Hub layout (`~/.cache/huggingface/hub/<repo>`),
/// which is the same layout mlx-audio-swift's internal HubApi reads from.
/// If we used `--local-dir`, the model would land in a custom path that the
/// inference code would then refuse to use (cache miss → re-download).
    static func pull(repo: String, to localDir: String? = nil) throws -> String {
        // Standard HF Hub cache layout: ~/.cache/huggingface/hub/models--<org>--<repo>
        let dest = localDir ?? defaultCachePath(for: repo)

        // Quick check — if config.json + a safetensors already exist locally,
        // skip the download. (mlx-audio-swift will do a deeper check at load time.)
        if FileManager.default.fileExists(atPath: dest) {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dest)) ?? []
            if contents.contains(where: { $0.hasSuffix(".safetensors") }) {
                return dest
            }
        }

        let env = ProcessInfo.processInfo.environment
        var merged = env
        merged["HF_ENDPOINT"] = env["HF_ENDPOINT"] ?? "https://hf-mirror.com"
        // Forward proxy settings so the download tool can reach the network.
        // `huggingface_hub` / `hf` / `uvx` all honour standard *_proxy env vars.
        for key in ["http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY",
                    "all_proxy", "ALL_PROXY", "no_proxy", "NO_PROXY"] {
            if let v = env[key], !v.isEmpty {
                merged[key] = v
            }
        }

        // Tool detection chain: hf → uvx hf → x uvx hf
        let candidates: [(label: String, tool: String, wrapperArgs: [String])] = [
            ("hf", "hf", []),
            ("uvx hf", "uvx", ["hf"]),
            ("x-cmd uvx hf", "x", ["uvx", "hf"]),
        ]
        for c in candidates {
            guard let path = findInPath(c.tool) else { continue }
            // --local-dir: hf writes files directly into <dest> instead of the
            // HF HubCache `models--<org>--<repo>/` layout. We need this because
            // mlx-audio-swift's TTS.loadModel reads from `mlx-audio/<repo>/`
            // (its own private layout), NOT from the HF HubCache.
            let argv = [path] + c.wrapperArgs + ["download", repo, "--local-dir", dest]
            _ = try runDownloader(label: c.label, argv: argv, env: merged)
            return dest
        }

        throw MlxError.pullFailed(
            "no hf / uvx / x-cmd found. install one: brew install uv, or x install uv"
        )
    }

    private static func findInPath(_ name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func runDownloader(
        label: String,
        argv: [String],
        env: [String: String]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        var procEnv = env
        process.environment = procEnv

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        print("Pulling via \(label) ...")
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw MlxError.pullFailed("\(label): \(errMsg)")
        }
        return ""
    }

    /// Default cache path: ~/.cache/huggingface/hub/mlx-audio/<repo-id-with-/-replaced>
    /// Matches the layout `Blaizzy/mlx-audio-swift`'s `ModelUtils` writes to
    /// when downloading models itself, so a `macsay pull`'d model is recognized
    /// as already-cached by `TTS.loadModel(...)` (no re-download).
    private static func defaultCachePath(for repo: String) -> String {
        let home = NSHomeDirectory()
        let subdir = repo.replacingOccurrences(of: "/", with: "_")
        return "\(home)/.cache/huggingface/hub/mlx-audio/\(subdir)"
    }
}