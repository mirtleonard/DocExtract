#!/usr/bin/env python3
"""Send a document + prompt to Gemini API and print the model response text.

Usage example:
  python gemini_document_prompt.py \
    --document /path/to/file.pdf \
    --prompt "Extract all invoice fields as plain text."
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path
from typing import Optional

try:
    from google import genai
except ModuleNotFoundError:
    print(
        "Missing dependency: google-genai. Install it with: pip install google-genai",
        file=sys.stderr,
    )
    raise SystemExit(1)

try:
    from dotenv import load_dotenv, find_dotenv
except ModuleNotFoundError:
    load_dotenv = None  # type: ignore[assignment]
    find_dotenv = None  # type: ignore[assignment]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload a document to Gemini Files API and query it with a prompt."
    )
    parser.add_argument(
        "--document",
        required=False, #True,
        type=Path,
        help="Path to the document file (PDF, TXT, DOCX, etc.).",
    )
    parser.add_argument(
        "--prompt",
        required=False, #True,
        help="Prompt/instruction applied to the uploaded document.",
    )
    parser.add_argument(
        "--model",
        default="gemini-2.5-flash",
        help="Gemini model name. Default: gemini-2.5-flash",
    )
    parser.add_argument(
        "--api-key",
        default=None,
        help="Gemini API key. If omitted, uses GEMINI_API_KEY or GOOGLE_API_KEY.",
    )
    parser.add_argument(
        "--keep-file",
        action="store_true",
        help="Keep uploaded file in Gemini Files API instead of deleting after response.",
    )
    parser.add_argument(
        "--wait-seconds",
        type=int,
        default=60,
        help="Max seconds to wait for uploaded file to become ACTIVE. Default: 60",
    )
    return parser.parse_args()


def resolve_api_key(explicit_key: Optional[str]) -> str:
    api_key = explicit_key or os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise ValueError(
            "Missing API key. Set GEMINI_API_KEY (or GOOGLE_API_KEY) or pass --api-key."
        )
    return api_key


def wait_until_active(client: genai.Client, file_name: str, max_wait_seconds: int) -> None:
    start = time.time()
    while True:
        current = client.files.get(name=file_name)
        state = getattr(current, "state", None)

        # SDK may return enum-like objects or plain strings.
        state_value = getattr(state, "name", str(state)) if state is not None else "UNKNOWN"

        if state_value == "ACTIVE":
            return
        if state_value == "FAILED":
            raise RuntimeError(f"File processing failed for {file_name}.")
        if time.time() - start > max_wait_seconds:
            raise TimeoutError(
                f"Timed out waiting for uploaded file to become ACTIVE (>{max_wait_seconds}s)."
            )
        time.sleep(2)


def run() -> int:
    if load_dotenv and find_dotenv:
        load_dotenv(find_dotenv(usecwd=True))

    args = parse_args()

    args.document = Path.home() / "Desktop/CNAS.pdf"
    args.prompt = "Extract fields from the document as plain text."
    args.model = "gemini-2.5-flash"
    args.keep_file = False
    args.wait_seconds = 60

    if not args.document.exists():
        print(f"Document does not exist: {args.document}", file=sys.stderr)
        return 1
    if not args.document.is_file():
        print(f"Document is not a file: {args.document}", file=sys.stderr)
        return 1

    try:
        api_key = resolve_api_key(args.api_key)
        client = genai.Client(api_key=api_key)

        uploaded = client.files.upload(file=args.document)
        wait_until_active(client, uploaded.name, max_wait_seconds=args.wait_seconds)

        response = client.models.generate_content(
            model=args.model,
            contents=[uploaded, args.prompt],
        )

        output_text = getattr(response, "text", None)
        if not output_text:
            raise RuntimeError("Gemini returned no text output.")
        print(output_text)

        if not args.keep_file:
            client.files.delete(name=uploaded.name)
        return 0

    except Exception as exc:  # noqa: BLE001
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(run())
