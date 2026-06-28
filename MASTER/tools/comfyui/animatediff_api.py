#!/usr/bin/env python3
"""Minimal ComfyUI AnimateDiff wrapper for MASTER VideoChain.

Exposes POST /api/animatediff/generate — patches workflow JSON, queues via ComfyUI /prompt,
polls /history, returns view_url.

Usage:
  COMFYUI_URL=http://127.0.0.1:8188 \\
  WORKFLOW_JSON=../../data/comfyui/animatediff_i2v.workflow.json \\
  python3 animatediff_api.py --port 8189
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib import error, request


def comfy_base() -> str:
    return os.environ.get("COMFYUI_URL", "http://127.0.0.1:8188").rstrip("/")


def workflow_path() -> Path:
    default = Path(__file__).resolve().parents[2] / "data" / "comfyui" / "animatediff_i2v.workflow.json"
    return Path(os.environ.get("WORKFLOW_JSON", str(default)))


def http_json(method: str, url: str, payload: dict | None = None, timeout: int = 120) -> dict:
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = request.Request(url, data=data, headers=headers, method=method)
    with request.urlopen(req, timeout=timeout) as res:
        return json.loads(res.read().decode("utf-8"))


def upload_image(path: str) -> str:
    boundary = f"ComfyUIBoundary{uuid.uuid4().hex}"
    filename = os.path.basename(path)
    mime = mimetypes.guess_type(path)[0] or "image/png"
    with open(path, "rb") as handle:
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="image"; filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
        ).encode("utf-8") + handle.read() + f"\r\n--{boundary}--\r\n".encode("utf-8")
    req = request.Request(
        f"{comfy_base()}/upload/image",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    with request.urlopen(req, timeout=120) as res:
        payload = json.loads(res.read().decode("utf-8"))
    return payload.get("name") or filename


def download_keyframe(source: str, dest: str) -> str:
    if source.startswith("http://") or source.startswith("https://"):
        with request.urlopen(source, timeout=120) as res:
            Path(dest).write_bytes(res.read())
        return dest
    if os.path.isfile(source):
        return source
    raise FileNotFoundError(f"keyframe not found: {source}")


def patch_workflow(workflow: dict, body: dict, image_name: str) -> dict:
    prompt = body.get("prompt", "")
    frame_count = int(body.get("frame_count") or body.get("duration", 3) * 8)
    loras = list(body.get("motion_loras") or [])
    strength = float(body.get("motion_lora_strength") or 0.75)
    strength_2 = float(body.get("motion_lora_2_strength") or 0.65)

    if "6" in workflow and "inputs" in workflow["6"]:
        workflow["6"]["inputs"]["text"] = prompt
    if "10" in workflow and "inputs" in workflow["10"]:
        workflow["10"]["inputs"]["image"] = image_name
    if "15" in workflow and "inputs" in workflow["15"]:
        workflow["15"]["inputs"]["frame_count"] = frame_count
    if loras and "22" in workflow and "inputs" in workflow["22"]:
        workflow["22"]["inputs"]["lora_name"] = loras[0]
        workflow["22"]["inputs"]["strength"] = strength
    if len(loras) > 1 and "23" in workflow and "inputs" in workflow["23"]:
        workflow["23"]["inputs"]["lora_name"] = loras[1]
        workflow["23"]["inputs"]["strength"] = strength_2
    return workflow


def wait_for_history(prompt_id: str, timeout: int = 900) -> dict:
    start = time.time()
    while time.time() - start < timeout:
        history = http_json("GET", f"{comfy_base()}/history/{prompt_id}")
        entry = history.get(prompt_id)
        if entry and entry.get("outputs"):
            return entry
        time.sleep(3)
    raise TimeoutError(f"ComfyUI timeout after {timeout}s")


def extract_video_ref(history: dict) -> dict:
    for node in (history.get("outputs") or {}).values():
        for bucket in ("gifs", "videos", "images"):
            for item in node.get(bucket) or []:
                if item.get("filename"):
                    return item
    raise RuntimeError("ComfyUI history contained no video output")


def generate_clip(body: dict) -> dict:
    workflow = json.loads(workflow_path().read_text(encoding="utf-8"))
    keyframe_src = body.get("image") or body.get("keyframe_url")
    if not keyframe_src:
        raise ValueError("missing image")

    temp_dir = Path(os.environ.get("TMPDIR", "/tmp")) / "master_animatediff"
    temp_dir.mkdir(parents=True, exist_ok=True)
    local_keyframe = str(temp_dir / f"keyframe_{uuid.uuid4().hex}.png")
    download_keyframe(keyframe_src, local_keyframe)
    image_name = upload_image(local_keyframe)

    patched = patch_workflow(workflow, body, image_name)
    client_id = str(uuid.uuid4())
    queued = http_json("POST", f"{comfy_base()}/prompt", {"prompt": patched, "client_id": client_id})
    prompt_id = queued.get("prompt_id")
    if not prompt_id:
        raise RuntimeError("ComfyUI queue missing prompt_id")

    history = wait_for_history(prompt_id)
    ref = extract_video_ref(history)
    params = {
        "filename": ref["filename"],
        "subfolder": ref.get("subfolder", ""),
        "type": ref.get("type", "output"),
    }
    query = "&".join(f"{key}={request.quote(str(value))}" for key, value in params.items())
    view_url = f"{comfy_base()}/view?{query}"
    return {"view_url": view_url, "output_url": view_url, "prompt_id": prompt_id}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_POST(self) -> None:
        if self.path != "/api/animatediff/generate":
            self.send_error(404, "not found")
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            body = json.loads(raw.decode("utf-8"))
            result = generate_clip(body)
            payload = json.dumps(result).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (error.URLError, TimeoutError, RuntimeError, ValueError, FileNotFoundError) as exc:
            payload = json.dumps({"error": str(exc)}).encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)


def main() -> None:
    parser = argparse.ArgumentParser(description="ComfyUI AnimateDiff wrapper for MASTER")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.environ.get("COMFYUI_WRAPPER_PORT", "8189")))
    args = parser.parse_args()
    server = HTTPServer((args.host, args.port), Handler)
    sys.stderr.write(f"animatediff wrapper on http://{args.host}:{args.port}\n")
    sys.stderr.write(f"comfyui={comfy_base()} workflow={workflow_path()}\n")
    server.serve_forever()


if __name__ == "__main__":
    main()