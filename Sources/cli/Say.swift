import Foundation
import AppKit
import AVFoundation
import ObjectiveC.runtime

/// Common language / region shortcuts for `--locale`.
struct LocaleShortcuts {
    static let map: [String: String] = [
        "ar": "ar-SA",
        "ca": "ca-ES",
        "cs": "cs-CZ",
        "da": "da-DK",
        "de": "de-DE",
        "el": "el-GR",
        "en": "en-US",
        "es": "es-ES",
        "fi": "fi-FI",
        "fr": "fr-FR",
        "he": "he-IL",
        "hi": "hi-IN",
        "hr": "hr-HR",
        "hu": "hu-HU",
        "id": "id-ID",
        "it": "it-IT",
        "ja": "ja-JP",
        "ko": "ko-KR",
        "ms": "ms-MY",
        "nb": "nb-NO",
        "nl": "nl-NL",
        "pl": "pl-PL",
        "pt": "pt-BR",
        "ro": "ro-RO",
        "ru": "ru-RU",
        "sk": "sk-SK",
        "sv": "sv-SE",
        "th": "th-TH",
        "tr": "tr-TR",
        "uk": "uk-UA",
        "vi": "vi-VN",
        "cn": "zh-CN",
        "hk": "zh-HK",
        "tw": "zh-TW",
        "us": "en-US",
        "gb": "en-GB",
        "au": "en-AU",
    ]

    static var options: [OptMeta] {
        map.sorted { $0.key < $1.key }.map { (key, locale) in
            OptMeta(name: "--\(key)", type: Bool.self, desc: "Shortcut for --locale \(locale)")
        }
    }
}

private let localeOptions: [OptMeta] = [
    OptMeta(
        name: "--locale",
        type: String.self,
        desc: "Locale identifier (default: $MACSAY_LOCALE, $LANG, or en-US)",
        multiple: true
    ),
] + LocaleShortcuts.options

/// Resolve a single locale (shortcut flags take precedence, then the first
/// `--locale` value, then the environment default).
private func resolveLocale(_ p: ParsedCmd) -> String {
    for (key, locale) in LocaleShortcuts.map.sorted(by: { $0.key < $1.key }) {
        if p.opt("--\(key)") as Bool? ?? false {
            return locale
        }
    }
    if let arr = p.opt("--locale") as [String]?, let first = arr.first {
        return first
    }
    let env = ProcessInfo.processInfo.environment
    if let v = env["MACSAY_LOCALE"], !v.isEmpty {
        return v
    }
    if let lang = env["LANG"], !lang.isEmpty, lang != "C", lang != "POSIX" {
        let base = lang.components(separatedBy: ".").first ?? lang
        let normalized = base.replacingOccurrences(of: "_", with: "-")
        if normalized.contains("-") {
            return normalized
        }
    }
    return "en-US"
}

enum SayCmd: Cmd {
    static let meta = CmdMeta(
        name: "macsay",
        desc: "Speak text aloud, auto-detecting mixed languages",
        opts: localeOptions + [
            OptMeta(name: "--rate", type: Double.self, desc: "Speech rate (words per minute, default: 200)", `default`: 200.0),
            OptMeta(name: "--pitch", type: Double.self, desc: "Pitch multiplier (0.5-2.0, default: 1.0)", `default`: 1.0),
            OptMeta(name: "--volume", type: Double.self, desc: "Volume (0.0-1.0, default: 1.0)", `default`: 1.0),
            OptMeta(name: "--wait", type: Bool.self, desc: "Wait for speech to finish before exiting (default: true)"),
            OptMeta(name: "--output", type: String.self, desc: "Save audio to file (AIFF format for nsspeech, WAV for mlx)"),
            OptMeta(name: "--engine", type: String.self, desc: "TTS engine: nsspeech (default) | mlx", `default`: "nsspeech"),
            OptMeta(name: "--mlx-model", type: String.self, desc: "MLX model: HF repo id (mlx-community/...) or local path", `default`: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"),
            OptMeta(name: "--mlx-speaker", type: String.self, desc: "MLX speaker name (Ryan / Aiden)", `default`: "Ryan"),
            OptMeta(name: "--mlx-voice-design", type: String.self, desc: "MLX voice design prompt (e.g. 'female, British narrator')"),
            OptMeta(name: "--mlx-ref-audio", type: String.self, desc: "MLX reference audio path (Base model voice clone)"),
            OptMeta(name: "--mlx-ref-text", type: String.self, desc: "MLX reference transcript"),
            OptMeta(name: "--mlx-lang", type: String.self, desc: "MLX language (English / Chinese / etc.)", `default`: "English"),
            OptMeta(name: "--json", type: Bool.self, desc: "Output JSON (default)"),
        ],
        args: [ArgMeta(name: "text", desc: "Text to speak", required: false)],
        run: { p in
            let locale = resolveLocale(p)
            let rate = p.opt("--rate") as Double? ?? 200.0
            let pitch = p.opt("--pitch") as Double? ?? 1.0
            let volume = p.opt("--volume") as Double? ?? 1.0
            let wait = p.opt("--wait") as Bool? ?? true
            let output = p.opt("--output") as String?
            let engine = p.opt("--engine") as String? ?? "nsspeech"

            // If no text provided, read from stdin
            var text: String? = p.arg(0)
            if text == nil || text?.isEmpty == true {
                text = p.opt("--text") as String?
            }
            if text == nil || text?.isEmpty == true {
                if let stdin = readLine(), !stdin.isEmpty {
                    text = stdin
                }
            }

            guard let text = text, !text.isEmpty else {
                cmdError("text required")
            }

            // Dispatch to the chosen engine.
            switch engine.lowercased() {
            case "mlx":
                try await runMlxNative(text: text, p: p, output: output, locale: locale)
            case "nsspeech", "":
                runNsSpeech(text: text, output: output, locale: locale)
            default:
                cmdError("unknown engine: \(engine) (use 'nsspeech' or 'mlx')")
            }
        }
    )
}

/// NSSpeechSynthesizer path: split by language and speak each segment.
private func runNsSpeech(text: String, output: String?, locale: String) {
    let segments = detectLanguages(text)
    if let outputPath = output {
        try? recordTTS(segments: segments, outputPath: outputPath)
        printJson(["ok": true, "engine": "nsspeech", "locale": locale, "text": text, "output": outputPath, "segments": segments.count])
    } else {
        for segment in segments {
            let synthesizer = NSSpeechSynthesizer()
            if let voice = findBestVoice(for: segment.locale) {
                synthesizer.setVoice(voice)
            }
            synthesizer.startSpeaking(segment.text)
            while synthesizer.isSpeaking {
                usleep(50_000)
            }
        }
        printJson(["ok": true, "engine": "nsspeech", "locale": locale, "text": text, "segments": segments.count])
    }
}

/// MLX path: in-process Swift MLX inference via mlx-audio-swift.
/// Always writes to a file; if no output is given, plays via afplay.
private func runMlxNative(text: String, p: ParsedCmd, output: String?, locale: String) async throws {
    let model = p.opt("--mlx-model") as String? ?? "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
    let speaker = p.opt("--mlx-speaker") as String? ?? "Ryan"
    let voiceDesign = p.opt("--mlx-voice-design") as String?
    let refAudio = p.opt("--mlx-ref-audio") as String?
    let refText = p.opt("--mlx-ref-text") as String?
    let lang = p.opt("--mlx-lang") as String? ?? "English"

    var config = MlxEngineNative.Config(
        model: model,
        speaker: speaker,
        refAudio: refAudio,
        refText: refText,
        lang: lang,
    )
    if let d = voiceDesign { config.voiceDesign = d }

    let outputURL: URL
    if let userPath = output {
        outputURL = URL(fileURLWithPath: userPath)
    } else {
        outputURL = URL(fileURLWithPath: "/tmp/macsay_mlx_output.wav")
    }

    do {
        let result = try await MlxEngineNative.synthesize(text: text, config: config, outputURL: outputURL)
        if output == nil {
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            p2.arguments = [result]
            try? p2.run()
            p2.waitUntilExit()
        }
        printJson(["ok": true, "engine": "mlx", "locale": locale, "text": text, "output": result, "model": model, "speaker": speaker])
    } catch let e as MlxEngineNative.MlxError {
        cmdError("mlx engine error: \(e)")
    } catch {
        cmdError("mlx engine error: \(error.localizedDescription)")
    }
}

enum VoicesCmd: Cmd {
    static let meta = CmdMeta(
        name: "voices",
        desc: "List available TTS voices",
        opts: [
            OptMeta(name: "--locale", type: String.self, desc: "Filter by locale (e.g. en-US, zh-CN)"),
            OptMeta(name: "--json", type: Bool.self, desc: "Output JSON (default)"),
        ],
        run: { p in
            let filter = p.opt("--locale") as String?
            let voices = NSSpeechSynthesizer.availableVoices
            let list: [[String: Any]] = voices.map { voice in
                let raw = voice.rawValue
                let parts = raw.components(separatedBy: ".")
                // com.apple.voice.compact.en-US.Samantha → parts = ["com","apple","voice","compact","en-US","Samantha"]
                let locale = parts.count >= 5 && parts[parts.count - 2].contains("-") ? parts[parts.count - 2] : ""
                if let filter = filter, !filter.isEmpty, locale != filter {
                    return [String: Any]()
                }
                let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
                return [
                    "voice": raw,
                    "locale": locale,
                    "name": attrs[.name] ?? "",
                    "gender": attrs[.gender] ?? "",
                    "age": attrs[.age] ?? "",
                ]
            }.filter { !$0.isEmpty }
            printJson(["ok": true, "count": list.count, "voices": list])
        }
    )
}

/// `macsay pull <repo>` — download an MLX-community model from Hugging Face.
/// Auto-detects hf / uvx / x-cmd uvx and uses whichever is in PATH.
/// Default repo: mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit
enum PullCmd: Cmd {
    static let meta = CmdMeta(
        name: "pull",
        desc: "Download an MLX model from Hugging Face (auto-detects hf / uvx / x-cmd). Default: Qwen3-TTS-1.7B-CustomVoice-8bit",
        opts: [
            OptMeta(name: "--hf-mirror", type: String.self, desc: "Hugging Face mirror endpoint", `default`: "https://hf-mirror.com"),
            OptMeta(name: "--dest", type: String.self, desc: "Local destination directory (default: ~/.cache/huggingface/hub/<repo>)"),
            OptMeta(name: "--json", type: Bool.self, desc: "Output JSON (default)"),
        ],
        args: [ArgMeta(name: "repo", desc: "Hugging Face repo id (default: mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit)")],
        run: { p in
            let repo: String
            if let r = p.arg(0), !r.isEmpty {
                repo = r
            } else {
                repo = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
            }
            let mirror = p.opt("--hf-mirror") as String? ?? "https://hf-mirror.com"
            let dest = p.opt("--dest") as String?

            // Apply HF_ENDPOINT (mirror) for this process so subprocess inherits it.
            setenv("HF_ENDPOINT", mirror, 1)

            do {
                let path = try MlxEngineNative.pull(repo: repo, to: dest)
                printJson([
                    "ok": true,
                    "repo": repo,
                    "path": path,
                    "mirror": mirror,
                ])
            } catch {
                cmdError("pull failed: \(error)")
            }
        }
    )
}

/// Auto-detect language segments in text.
private func detectLanguages(_ text: String) -> [(locale: String, text: String)] {
    var segments: [(locale: String, text: String)] = []
    var currentText = ""
    var currentLang = ""

    for char in text {
        let lang = detectLanguage(char)
        if lang != currentLang && !currentText.isEmpty {
            let trimmed = currentText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                segments.append((locale: currentLang, text: trimmed))
            }
            currentText = ""
        }
        currentText.append(char)
        currentLang = lang
    }

    let trimmed = currentText.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty && !currentLang.isEmpty {
        segments.append((locale: currentLang, text: trimmed))
    }

    if segments.count <= 1 {
        return [("", text)]
    }
    return segments
}

/// Detect language of a single character by Unicode range.
private func detectLanguage(_ char: Character) -> String {
    guard let scalar = char.unicodeScalars.first else { return "en-US" }
    let code = scalar.value

    if (0x4E00...0x9FFF).contains(code) || (0x3400...0x4DBF).contains(code) {
        return "zh-CN"
    }
    if (0x3040...0x309F).contains(code) || (0x30A0...0x30FF).contains(code) {
        return "ja-JP"
    }
    if (0xAC00...0xD7AF).contains(code) || (0x1100...0x11FF).contains(code) {
        return "ko-KR"
    }
    if (0x0400...0x04FF).contains(code) {
        return "ru-RU"
    }
    if (0x0600...0x06FF).contains(code) {
        return "ar-SA"
    }
    if (0x0E00...0x0E7F).contains(code) {
        return "th-TH"
    }
    return "en-US"
}

/// Find the best compact female voice for a locale.
private func findBestVoice(for locale: String) -> NSSpeechSynthesizer.VoiceName? {
    let allVoices = NSSpeechSynthesizer.availableVoices
    let preference: [String]
    switch locale {
    case "zh-CN", "zh-HK", "zh-TW": preference = ["Tingting", "Sin-ji", "Mei-Jia"]
    case "en-US", "en-GB", "en-AU": preference = ["Samantha", "Flo"]
    case "ja-JP": preference = ["Kyoko"]
    case "ko-KR": preference = ["Yuna"]
    default: return nil
    }
    for name in preference {
        for voice in allVoices {
            if voice.rawValue.contains(name) {
                return voice
            }
        }
    }
    return nil
}

/// Save TTS output to a file using NSSpeechSynthesizer's private save-to-file API.
private func recordTTS(segments: [(locale: String, text: String)], outputPath: String) throws {
    var tempFiles: [String] = []
    for (index, segment) in segments.enumerated() {
        let tempPath = "/tmp/macsay_segment_\(index).aiff"
        tempFiles.append(tempPath)

        let synthesizer = NSSpeechSynthesizer()
        if let voice = findBestVoice(for: segment.locale) {
            synthesizer.setVoice(voice)
        }

        let selector = NSSelectorFromString("startSpeakingString:toURL:")
        if synthesizer.responds(to: selector) {
            typealias Func = @convention(c) (AnyObject, Selector, NSString, NSURL) -> Bool
            let method = class_getInstanceMethod(type(of: synthesizer), selector)
            let imp = method_getImplementation(method!)
            let function = unsafeBitCast(imp, to: Func.self)
            _ = function(synthesizer, selector, segment.text as NSString, URL(fileURLWithPath: tempPath) as NSURL)
        }

        while synthesizer.isSpeaking {
            usleep(50_000)
        }
    }

    concatenateAudioFiles(tempFiles, output: outputPath)

    for temp in tempFiles {
        try? FileManager.default.removeItem(atPath: temp)
    }
}

/// Concatenate multiple AIFF audio files into one output file using AVAudioFile.
private func concatenateAudioFiles(_ inputPaths: [String], output: String) {
    guard !inputPaths.isEmpty else { return }

    var combinedBuffer: AVAudioPCMBuffer?
    var format: AVAudioFormat?

    for path in inputPaths {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { continue }

        if format == nil {
            format = file.processingFormat
            if let buf = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: AVAudioFrameCount(file.length)) {
                combinedBuffer = buf
            }
        }

        if let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) {
            try? file.read(into: buffer)
            if let combined = combinedBuffer, let fmt = format {
                let newLength = combined.frameLength + buffer.frameLength
                if combined.frameCapacity < newLength {
                    if let newBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: newLength) {
                        newBuf.frameLength = combined.frameLength
                        let dst = newBuf.floatChannelData![0]
                        let src = combined.floatChannelData![0]
                        memcpy(dst, src, Int(combined.frameLength) * Int(fmt.streamDescription.pointee.mBytesPerFrame))
                        combinedBuffer = newBuf
                    }
                }
                if let combined = combinedBuffer {
                    let dst = combined.floatChannelData![0]
                    let src = buffer.floatChannelData![0]
                    memcpy(dst + Int(combined.frameLength), src, Int(buffer.frameLength) * Int(format!.streamDescription.pointee.mBytesPerFrame))
                    combined.frameLength = newLength
                }
            }
        }
    }

    if let combinedBuffer = combinedBuffer, let format = format {
        if let outFile = try? AVAudioFile(forWriting: URL(fileURLWithPath: output), settings: format.settings) {
            try? outFile.write(from: combinedBuffer)
        }
    }
}