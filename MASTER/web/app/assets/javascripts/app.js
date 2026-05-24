"use strict";

document.addEventListener("turbo:load", () => {
  const input = document.getElementById("input");
  const status = document.getElementById("status");
  const body = document.body;
  if (!input || !status || !body) return;

  const runtime = {
    frame: 0,
    hidden: document.hidden,
    busy: false,
    lastInputHeight: input.scrollHeight
  };

  const spinner = ["*", "@", "#", "&", "%"];

  function setProfile() {
    const coarse = matchMedia("(pointer: coarse)").matches;
    const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const battery = runtime.hidden || coarse || reducedMotion;
    body.dataset.runtimeProfile = battery ? "battery" : "full";
    body.dataset.runtimeVisible = runtime.hidden ? "false" : "true";
  }

  function autosizeInput() {
    input.style.height = "auto";
    const nextHeight = Math.min(input.scrollHeight, window.innerHeight * 0.4);
    if (nextHeight === runtime.lastInputHeight) return;
    input.style.height = `${nextHeight}px`;
    runtime.lastInputHeight = nextHeight;
  }

  function setStatus(text, state = "idle") {
    status.textContent = text;
    status.dataset.runtimeStatus = state;
  }

  function tick() {
    if (!runtime.hidden && runtime.busy) {
      setStatus(`thinking ${spinner[runtime.frame % spinner.length]}`, "busy");
      runtime.frame += 1;
    }
    requestAnimationFrame(tick);
  }

  input.addEventListener("input", () => {
    autosizeInput();
    runtime.busy = input.value.trim().length > 0;
    if (!runtime.busy) setStatus("ready");
  }, { passive: true });

  input.addEventListener("keydown", event => {
    if (event.key !== "Enter" || event.shiftKey) return;
    runtime.busy = true;
    setStatus("sending", "busy");
  });

  document.addEventListener("visibilitychange", () => {
    runtime.hidden = document.hidden;
    setProfile();
    if (runtime.hidden) setStatus("paused");
  }, { passive: true });

  window.addEventListener("resize", autosizeInput, { passive: true });

  setProfile();
  autosizeInput();
  setStatus("ready");
  requestAnimationFrame(tick);
});
