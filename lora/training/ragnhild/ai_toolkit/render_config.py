#!/usr/bin/env python3
"""Inject paths and prompts into train_ragnhild.yaml for ai-toolkit."""

from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("warn: PyYAML missing in ai-toolkit environment")

ROOT = Path(__file__).resolve().parent
BASE = ROOT / "train_ragnhild.yaml"
PROMPTS = ROOT / "prompts.yaml"


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"warn: expected mapping in {path}")
    return data


def build(mode: str) -> dict:
    config = load(BASE)
    prompts = load(PROMPTS)
    process = config["config"]["process"][0]

    process["training_folder"] = str(ROOT / "weights")
    process["datasets"][0]["folder_path"] = str(ROOT / "dataset")
    process["sample"]["prompts"] = prompts["prompts"]
    process["sample"]["neg"] = prompts["negative"]

    if mode == "generate":
        train = copy.deepcopy(process["train"])
        train["start_step"] = train["steps"]
        train["force_first_sample"] = True
        process["train"] = train

    return config


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("train", "generate"), default="train")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    with args.output.open("w", encoding="utf-8") as handle:
        yaml.dump(build(args.mode), handle, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f"ok: rendered {args.mode} -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())