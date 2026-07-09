#!/usr/bin/env python3
"""Verify Hugging Face auth and FLUX.1-dev gate before train or generate."""

from __future__ import annotations

import os
import sys

FLUX_REPO = os.environ.get("RAGNHILD_FLUX_MODEL", "black-forest-labs/FLUX.1-dev")
FLUX_URL = f"https://huggingface.co/{FLUX_REPO}"
TOKEN_PATHS = (
    os.path.expanduser("~/.cache/huggingface/token"),
    os.path.expanduser("~/.huggingface/token"),
)


def read_token() -> str | None:
    for key in ("HF_TOKEN", "HUGGINGFACE_HUB_TOKEN"):
        value = os.environ.get(key, "").strip()
        if value:
            return value
    for path in TOKEN_PATHS:
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as handle:
                value = handle.read().strip()
            if value:
                return value
    return None


def local_flux_path() -> str | None:
    path = os.environ.get("RAGNHILD_FLUX_MODEL_PATH", "").strip()
    return path if path and os.path.isdir(path) else None


def gated(exc: Exception) -> bool:
    message = str(exc)
    return (
        "GatedRepoError" in type(exc).__name__
        or "403" in message
        or "authorized list" in message
    )


def main() -> int:
    local = local_flux_path()
    if local:
        print(f"ok: local FLUX at {local}")
        return 0

    token = read_token()
    if not token:
        print("warn: Hugging Face auth missing", file=sys.stderr)
        print("fix: set HF_TOKEN or run hf auth login", file=sys.stderr)
        return 1

    try:
        from huggingface_hub import HfApi, hf_hub_download
    except ImportError:
        print("warn: huggingface_hub not installed", file=sys.stderr)
        return 1

    api = HfApi(token=token)
    try:
        user = api.whoami()["name"]
        print(f"ok: HF user {user}")
    except Exception as exc:  # noqa: BLE001
        print(f"warn: invalid token ({exc})", file=sys.stderr)
        return 1

    try:
        index = hf_hub_download(FLUX_REPO, "model_index.json", token=token)
        print(f"ok: authorized for {FLUX_REPO}")
        print(f"ok: model_index {index}")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"warn: cannot access {FLUX_REPO}", file=sys.stderr)
        if gated(exc):
            print("fix: open", FLUX_URL, f"as {user}, accept license, rerun", file=sys.stderr)
        else:
            print(f"reason: {exc}", file=sys.stderr)
        print("fix: or set RAGNHILD_FLUX_MODEL_PATH to local FLUX.1-dev", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())