# macsay

macOS text-to-speech CLI with multi-language support. Built on Apple's `NSSpeechSynthesizer`.

## Features

- **Auto language detection**: speak mixed Chinese/English/Japanese/Korean text in one command
- **Multi-language**: `--locale` shortcut flags (`--cn`, `--en`, `--ja`, `--ko`, etc.)
- **Save to file**: export TTS output to AIFF (`--output`)
- **JSON output**: programmatic-friendly JSON results
- **Pluggable engines**: `--engine` flag (currently `nsspeech`, future: mlx)

## Why

System `say` produces poor Chinese/English pronunciation in mixed sentences. `macsay` automatically splits input by language and speaks each segment with the best voice for that locale.

## Build

```sh
swift build -c release
cp .build/release/macsay ~/.local/bin/
```

## Usage

```sh
# Speak mixed text (auto-detects language per segment)
macsay say "hello.你好天气"

# Specific locale (overrides LANG)
macsay say "what is the weather" --en
macsay say "你好" --cn

# Save to AIFF file
macsay say "hello.你好天气" --output /tmp/speech.aiff

# List available voices
macsay voices
macsay voices --locale en-US

# Read from stdin
echo "hello world" | macsay say
```

## Voice Selection

`macsay` automatically picks the best compact female voice per locale:

| Locale | Voice |
|--------|-------|
| zh-CN | Tingting |
| zh-HK | Sinji |
| zh-TW | Meijia |
| en-US | Samantha |
| en-GB | Daniel |
| en-AU | Karen |
| ja-JP | Kyoko |
| ko-KR | Yuna |

## License

MIT