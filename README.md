# macsay

> macOS 端的多语种文本转语音 CLI；内嵌 Apple NSSpeechSynthesizer（零依赖），可切换到 Qwen3-TTS via MLX（更自然、可自定义声音）。自动检测中英日韩混合文本，按段选用最合适的 voice。

## TL;DR

零依赖播放（默认 `nsspeech` 引擎）
```sh
macsay "hello"
macsay "你好世界"
macsay "hello.你好天气.こんにちは"   # 混合语言自动分段
```

高保真 MLX（Qwen3-TTS）
```sh
./Scripts/build-metallib.sh            # 一次性（需 Xcode + Metal toolchain）
macsay pull                           # 下载 Qwen3-TTS-1.7B-CustomVoice-8bit
macsay "Hello world" --engine mlx
```

按语言选 voice
```sh
macsay "你好" --cn
macsay "Hello" --en
macsay "こんにちは" --ja
```

导出音频
```sh
macsay "text" --output /tmp/speech.aiff
macsay "text" --engine mlx --output /tmp/qwen3.wav
```

## Synopsis

```
macsay [OPTIONS] <text>           # speak
macsay voices [--locale LOCALE]    # 列出可用 voice
macsay pull [<repo>]               # 下载 MLX 模型（默认 Qwen3-TTS-1.7B）
macsay pull --hf-mirror URL        # 自定义 mirror
```

## Options

`--engine nsspeech|mlx`            引擎选择（默认 nsspeech）
`--output PATH`                     写到音频文件（nsspeech=AIFF / mlx=WAV）
`--rate N`                          语速（nsspeech）
`--pitch N`                         音调（nsspeech）
`--volume N`                        音量（nsspeech）

MLX 子选项
`--mlx-model REPO-OR-PATH`          HF repo id 或本地路径
`--mlx-speaker NAME`                ryan / aiden / ono_anna / sohee / serena / ...
`--mlx-voice-design "..."`          VoiceDesign 模型的声音描述 prompt
`--mlx-ref-audio PATH`              Base 模型声音克隆参考音
`--mlx-ref-text TEXT`               参考音对应文字稿
`--mlx-lang LANG`                   English / Chinese / Japanese / Korean / ...

Locale 简写（按 `--locale XX-YY` 解析；nsspeech 引擎会按它选 voice）
`--ar / --au / --ca / --cn / --cs / --da / --de / --el / --en / --es / --fi / --fr / --gb / --he / --hi / --hk / --hr / --hu / --id / --it / --ja / --ko / --ms / --nb / --nl / --pl / --pt / --ro / --ru / --sk / --sv / --th / --tr / --tw / --uk / --us / --vi`

`--json`                            JSON 输出
`--help` / `-h`                     帮助

## Engines

| 引擎 | 后端 | 安装 | 质量 | 速度 |
|------|------|------|------|------|
| `nsspeech`（默认） | Apple NSSpeechSynthesizer | 无 | ⭐⭐⭐ | 即时 |
| `mlx` | Qwen3-TTS via `Blaizzy/mlx-audio-swift` | 一次性 `macsay pull` | ⭐⭐⭐⭐⭐ | ~30s/段 |

## 引擎选择建议

短句 / 脚本 / 一次性：默认 `nsspeech` 即可。
长句 / 想要"自然人声" / 中文 / 日语：`--engine mlx`。
多语言段落同一文本：`nsspeech`（自动分段）。

## 从源码编译

```sh
git clone https://github.com/ljh-sh/macsay
cd macsay

# MLX 引擎需要 Xcode + Metal toolchain（一次性生成 mlx.metallib）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift build -c release
./Scripts/build-metallib.sh
strip .build/release/macsay     # 可选：缩减约 50%
cp .build/release/macsay ~/.local/bin/
```

非 MLX 用户只跑 `swift build -c release` 即可，不用 Xcode。

## License

MIT