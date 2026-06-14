#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def load_corpus(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8").strip()
    blocks = [block.strip() for block in text.split("\n\n") if block.strip()]
    if not blocks:
        raise SystemExit(f"Prompt corpus is empty: {path}")
    return blocks


def build_prompt(target_chars: int, corpus_blocks: list[str]) -> str:
    header = (
        "This is a deterministic benchmark prompt. "
        "It repeats technical content to keep tokenization stable.\n\n"
    )
    chunks: list[str] = [header]
    total = len(header)
    index = 0
    while total < target_chars:
        block = corpus_blocks[index % len(corpus_blocks)]
        piece = block.strip() + "\n\n"
        chunks.append(piece)
        total += len(piece)
        index += 1
    return "".join(chunks).strip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus-file", default="configs/prompt_corpus.txt")
    parser.add_argument("--target-context", type=int, required=True)
    parser.add_argument("--max-new-tokens", type=int, default=256)
    parser.add_argument("--reserve-tokens", type=int, default=1024)
    parser.add_argument("--chars-per-token", type=float, default=4.0)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    corpus_path = Path(args.corpus_file)
    target_prompt_tokens = max(64, args.target_context - args.max_new_tokens - args.reserve_tokens)
    target_chars = int(target_prompt_tokens * args.chars_per_token)

    prompt = build_prompt(target_chars, load_corpus(corpus_path))
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(prompt, encoding="utf-8")

    print(f"prompt_path={output_path}")
    print(f"target_context={args.target_context}")
    print(f"target_prompt_tokens_approx={target_prompt_tokens}")
    print(f"prompt_chars={len(prompt)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
