#!/usr/bin/env python3
"""macsay MLX helper — wraps mlx_audio's Qwen3-TTS Python API.

Invoked by `macsay say --engine mlx ...`. The Swift side passes text, model
path, voice/speaker config, and an output directory; we synthesize and write
the audio file.
"""
import argparse
import os
import sys

import mlx.core as mx
from mlx_audio.tts.utils import load_model


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--voice-design", default=None,
                    help="VoiceDesign mode prompt, e.g. 'female, British narrator'")
    ap.add_argument("--speaker", default="Ryan",
                    help="CustomVoice speaker (e.g. Ryan, Aiden)")
    ap.add_argument("--instruct", default=None,
                    help="Style instruction for CustomVoice")
    ap.add_argument("--ref-audio", default=None,
                    help="Reference audio for voice clone (Base model)")
    ap.add_argument("--ref-text", default=None,
                    help="Reference transcript for voice clone")
    ap.add_argument("--lang", default="English")
    ap.add_argument("--format", default="wav")
    ap.add_argument("--join", action="store_true", default=True)
    ap.add_argument("--no-join", dest="join", action="store_false")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    os.makedirs(args.output, exist_ok=True)
    model = load_model(args.model)

    if args.ref_audio:
        # Base model — voice clone with reference audio
        from mlx_audio.tts.generate import generate_audio
        generate_audio(
            model=model,
            text=args.text,
            lang_code=args.lang,
            ref_audio=args.ref_audio,
            ref_text=args.ref_text or "",
            output_path=args.output,
            file_prefix="out",
            audio_format=args.format,
            join_audio=args.join,
            verbose=args.verbose,
        )
    else:
        # CustomVoice / VoiceDesign — manual line-splitting loop
        segments = [s.strip() for s in args.text.split("\n") if s.strip()]
        audio = []
        for i, text in enumerate(segments):
            if args.verbose:
                print(f"{i+1}/{len(segments)} {text}", file=sys.stderr)
            if args.voice_design:
                results = model.generate_voice_design(
                    text=text, instruct=args.voice_design, verbose=args.verbose,
                )
            else:
                results = model.generate_custom_voice(
                    text=text, speaker=args.speaker,
                    instruct=args.instruct or "", verbose=args.verbose,
                )
            for r in results:
                audio.append(r.audio)

        from mlx_audio.audio_io import write as audio_write
        out_path = os.path.join(args.output, f"out.{args.format}")
        audio_write(out_path, mx.concatenate(audio, axis=0), model.sample_rate)
        print(out_path)


if __name__ == "__main__":
    main()