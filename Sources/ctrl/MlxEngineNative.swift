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
}