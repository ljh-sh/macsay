// MlxEngineNative.swift
//
// Swift-native MLX engine (experimental / not yet wired into SayCmd).
//
// Status (2026-06-29): mlx-audio-swift + mlx-swift are integrated as SwiftPM
// dependencies and the code compiles, but macsay currently can't RUN the
// Swift native path because:
//   - mlx-swift requires the Metal toolchain (not bundled with Xcode CLT)
//   - Xcode 26.5 on this machine is missing CoreSimulator.framework
//   - `xcodebuild -downloadComponent MetalToolchain` hangs waiting for a
//     missing interactive prompt
//
// To enable in the future:
//   1. Fix the Xcode install (CoreSimulator + Metal toolchain)
//   2. Add `import MLX / MLXAudioCore / MLXAudioTTS` paths to Package.swift
//      (already in main Package.swift, but the Python path is the default)
//   3. Switch SayCmd's MLX dispatch from `runMlx` (Python) to `runMlxNative`
//      (this file)
//   4. Delete Resources/qwen3_tts_helper.py and the spawn code in MlxEngine.swift
//
// Tested-by: compiles clean under `DEVELOPER_DIR=/Applications/Xcode.app/...`
// swift build with mlx-swift 0.31.4 + mlx-audio-swift main. Runtime blocked
// by missing metal toolchain on this machine.

import Foundation
#if canImport(MLX)
import MLX
import MLXAudioCore
import MLXAudioTTS

@available(macOS 14.0, *)
enum MlxEngineNative {
    struct Config {
        var model: String = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
        var voiceDesign: String?
        var speaker: String = "Ryan"
        var instruct: String?
        var refAudio: String?
        var refText: String?
        var lang: String = "English"
    }

    enum MlxError: Error {
        case modelNotFound(String)
        case synthesisFailed(String)
    }

    /// Run TTS in-process via mlx-audio-swift. Returns the WAV file path.
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
}
#endif