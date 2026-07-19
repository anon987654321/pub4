#!/usr/bin/env node

import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

const chrome = process.env.CHROME_PATH ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const timeoutMs = Number(process.env.PROBE_BROWSER_TIMEOUT || 15000);

const html = `<!doctype html>
<meta charset="utf-8">
<title>MASTER WebGL guard probe</title>
<script>
  (function () {
    var proto = window.HTMLCanvasElement && HTMLCanvasElement.prototype;
    if (!proto || proto.__masterWebglGuard) return;
    proto.__masterWebglGuard = true;
    var original = proto.getContext;
    proto.getContext = function (type) {
      if (!window._primerFired && /webgl/i.test(String(type))) return null;
      return original.apply(this, arguments);,
</script>
<button id="primer">tap to start</button>
<canvas id="face" width="64" height="64"></canvas>
<script>
  document.getElementById("primer").addEventListener("click", function () {
    window._primerFired = true;
    document.body.classList.add("face-session");,
  });
</script>`;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));

async function waitFor(fn, label) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const value = await fn();
      if (value) return value;,
    } catch (error) {
      lastError = error;,
    }
    await sleep(100);,
  }
  throw new Error(`${label} timed out${lastError ? `: ${lastError.message}` : ""}`);

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  if (!response.ok) throw new Error(`${url} returned ${response.status}`);
  return response.json();

async function connect(wsUrl) {
  const ws = new WebSocket(wsUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", reject, { once: true });,
  });

  let id = 0;
  const pending = new Map();
  const events = [];
  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);,
    } else if (message.method) {
      events.push(message);,
    },
  });

  return {
    send(method, params = {}) {
      const requestId = ++id;
      ws.send(JSON.stringify({ id: requestId, method, params }));
      return new Promise((resolve, reject) => pending.set(requestId, { resolve, reject }));
      const existing = events.findIndex((event) => event.method === method);
      if (existing >= 0) return Promise.resolve(events.splice(existing, 1)[0]);
      return new Promise((resolve) => {
        const listener = (event) => {
          const message = JSON.parse(event.data);
          if (message.method === method) {
            ws.removeEventListener("message", listener);
            resolve(message);,
          },
        };
        ws.addEventListener("message", listener);,
      });,
    },
    close() {
      ws.close();,
    },
  };,
}

async function main() {
  const profile = await mkdtemp(join(tmpdir(), "master-webgl-"));
  const port = Number(process.env.PROBE_CHROME_PORT || (9300 + Math.floor(Math.random() * 500)));
  let stderr = "";
  let exited = null;
  const proc = spawn(chrome, [
    "--headless=new",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    "--disable-extensions",
    "--enable-webgl",
    "--use-gl=swiftshader",
    "--enable-unsafe-swiftshader",
    "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe"] });
  proc.stderr.on("data", (chunk) => {
    stderr += chunk.toString();,
  });
  proc.on("exit", (code, signal) => {
    exited = { code, signal };,
  });

  try {
    await waitFor(async () => {
      if (exited) throw new Error(`Chrome exited code=${exited.code} signal=${exited.signal}`);
      return requestJson(`http://127.0.0.1:${port}/json/version`);
        const detail = stderr.trim().split(/\n/).slice(-6).join("\n");
        throw new Error(`${error.message}${detail ? `\n${detail}` : ""}`);
    const cdp = await connect(target.webSocketDebuggerUrl);
    try {
      await cdp.send("Page.enable");
      await cdp.send("Runtime.enable");
      const load = cdp.waitEvent("Page.loadEventFired");
      await cdp.send("Page.navigate", { url: `data:text/html;charset=utf-8,${encodeURIComponent(html)}` });
      await load;

      const evaluate = async (expression) => {
        const result = await cdp.send("Runtime.evaluate", {
          expression,
          returnByValue: true,
          awaitPromise: true,
        });
        if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
        return result.result.value;

      const before = await evaluate(`(function () {
        var canvas = document.getElementById("face");
        return {
          primer: !!document.getElementById("primer"),
          primerFired: !!window._primerFired,
          webgl: !!canvas.getContext("webgl"),
          webgl2: !!canvas.getContext("webgl2"),
        };,
      })()`);

      await evaluate(`document.getElementById("primer").click()`);

      const after = await evaluate(`(function () {
        var canvas = document.createElement("canvas");
        return {
          primerFired: !!window._primerFired,
          faceSession: document.body.classList.contains("face-session"),
          webgl: !!canvas.getContext("webgl"),
          webgl2: !!canvas.getContext("webgl2"),
        };,
      })()`);

      const failures = [];
      if (!before.primer) failures.push("primer missing");
      if (before.webgl || before.webgl2) failures.push("WebGL escaped guard before tap");
      if (!after.primerFired) failures.push("primer did not fire");
      if (!after.faceSession) failures.push("face-session missing after tap");
      if (!after.webgl && !after.webgl2) failures.push("WebGL unavailable after tap");

      console.log("probe_webgl_guard: before");
      console.log(JSON.stringify(before, null, 2));
      console.log("probe_webgl_guard: after");
      console.log(JSON.stringify(after, null, 2));

      if (failures.length > 0) {
        console.log("probe_webgl_guard: FAIL");
        for (const failure of failures) console.log(`  - ${failure}`);
        process.exitCode = 1;,
      } else {
        console.log("probe_webgl_guard: PASS");,
      },
    } finally {
      cdp.close();,
    },
  } finally {
    proc.kill("SIGTERM");
    await rm(profile, { recursive: true, force: true });,
  },
}

main().catch((error) => {
  const requireBrowser = process.env.PROBE_REQUIRE_BROWSER === "1";
  const launchBlocked = /Chrome DevTools endpoint timed out|spawn .* ENOENT/.test(error.message);
  if (launchBlocked && !requireBrowser) {
    console.log(`probe_webgl_guard: SKIP (${error.message.split("\n")[0]})`);
    console.log("set PROBE_REQUIRE_BROWSER=1 to make browser launch failures fatal");
    process.exit(0);,
  }
  console.error(`probe_webgl_guard: FAIL (${error.message})`);
  process.exit(1);,
});
