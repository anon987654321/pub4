#!/usr/bin/env python3
"""Preflight check for Ragnhild FLUX LoRA train/generate jobs."""

from __future__ import annotations

import os
import sys


FLUX_REPO = os.environ.get("RAGNHILD_FLUX_MODEL", "black-forest-labs/FLUX.1-dev")
FLUX_LICENSE_URL = f"https://huggingface.co/{FLUX_REPO}"


def token() -> str | None:
    for key in ("HF_TOKEN", "HUGGINGFACE_HUB_TOKEN"):
        value = os.environ.get(key, "").strip()
        if value:
            return value

    for path in (
        os.path.expanduser("~/.cache/huggingface/token"),
        os.path.expanduser("~/.huggingface/token"),
    ):
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as handle:
                value = handle.read().strip()
            if value:
                return value
    return None


def local_flux_path() -> str | None:
    override = os.environ.get("RAGNHILD_FLUX_MODEL_PATH", "").strip()
    if override and os.path.isdir(override):
        return override
    return None


def main() -> int:
    local_path = local_flux_path()
    if local_path:
        print(f"OK: using local FLUX model at {local_path}")
        return 0

    auth = token()
    if not auth:
        print("BLOCKED: Hugging Face auth not found.", file=sys.stderr)
        print("Set HF_TOKEN or run: hf auth login", file=sys.stderr)
        return 1

    try:
        from huggingface_hub import HfApi, hf_hub_download
    except ImportError:
        print("BLOCKED: huggingface_hub is not installed in the active Python env.", file=sys.stderr)
        return 1

    api = HfApi(token=auth)
    try:
        user = api.whoami()["name"]
        print(f"HF user: {user}")
    except Exception as exc:  # noqa: BLE001
        print(f"BLOCKED: Hugging Face token is invalid ({exc}).", file=sys.stderr)
        return 1

    try:
        path = hf_hub_download(FLUX_REPO, "model_index.json", token=auth)
        print(f"OK: authorized for {FLUX_REPO}")
        print(f"model_index: {path}")
        return 0
    except Exception as exc:  # noqa: BLE001
        message = str(exc)
        print(f"BLOCKED: cannot download {FLUX_REPO}", file=sys.stderr)
        if "GatedRepoError" in type(exc).__name__ or "403" in message or "authorized list" in message:
            print("Reason: account is logged in but not approved for this gated model.", file=sys.stderr)
            print(f"Fix: open {FLUX_LICENSE_URL} while logged in as {user}, click Agree, then rerun.", file=sys.stderr)
        else:
            print(f"Reason: {exc}", file=sys.stderr)
        print("Alternative: set RAGNHILD_FLUX_MODEL_PATH to a local FLUX.1-dev checkout.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())