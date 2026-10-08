// Compact task/evidence projection. Long-running work leaves the chat stream;
// this surface gives it a stable visual identity and recoverable state.
(() => {
  "use strict";

  let rail = null;

  function ensureRail() {
    if (rail?.isConnected) return rail;
    rail = document.getElementById("master-task-rail");
    if (rail) return rail;
    rail = document.createElement("aside");
    rail.id = "master-task-rail";
    rail.className = "master-task-rail";
    rail.setAttribute("aria-label", "MASTER tasks");
    rail.hidden = true;
    document.body.appendChild(rail);
    return rail;
  }

  function label(state) {
    return ({
      "queued": "queued", "active": "working", "waiting-human": "waiting for you",
      "waiting-network": "waiting for network", "waiting-model": "waiting for model",
      "complete": "complete", "failed": "failed", "cancelled": "cancelled"
    })[state] || state;
  }

  function render() {
    const root = ensureRail();
    const snapshot = window.MasterInteraction?.snapshot?.();
    const tasks = snapshot?.task?.records || [];
    const tools = snapshot?.tool?.records || [];
    root.replaceChildren();
    if (!tasks.length && !tools.length) {
      root.hidden = true;
      return;
    }
    root.hidden = false;

    tasks.slice(-12).forEach((task) => {
      const item = document.createElement("article");
      item.className = "master-task";
      item.dataset.taskId = task.id;
      item.dataset.state = task.state;
      const title = document.createElement("strong");
      title.textContent = task.kind;
      const status = document.createElement("span");
      status.textContent = label(task.state);
      status.className = "master-task-status";
      const meta = document.createElement("small");
      meta.textContent = task.provenance?.source ? String(task.provenance.source) : "";
      item.append(title, status, meta);
      if (task.state === "failed") {
        const retry = document.createElement("button");
        retry.type = "button";
        retry.textContent = "retry";
        retry.addEventListener("click", () => window.MasterInteraction?.taskUpdate?.(task.id, "active", { retry: true }));
        item.append(retry);
      }
      root.appendChild(item);
    });

    tools.slice(-8).forEach((tool) => {
      const item = document.createElement("div");
      item.className = "master-tool";
      item.textContent = String(tool.data?.label || tool.data?.name || "tool") + " — " + label(tool.state);
      root.appendChild(item);
    });
  }

  function task(kind, data, provenance) {
    const id = window.MasterInteraction?.taskCreate?.(kind, data, provenance);
    render();
    return id;
  }

  function update(id, state, data) {
    const result = window.MasterInteraction?.taskUpdate?.(id, state, data);
    render();
    return result;
  }

  function tool(id, state, data, provenance) {
    const result = window.MasterInteraction?.toolUpdate?.(id, state, data, provenance);
    render();
    return result;
  }

  function evidence(type, data, provenance) {
    const id = window.MasterInteraction?.remember?.(type, data, provenance);
    render();
    return id;
  }

  ["task:queued", "task:active", "task:waiting-human", "task:waiting-network", "task:waiting-model",
   "task:complete", "task:failed", "task:cancelled", "tool:queued", "tool:active", "tool:retry",
   "tool:complete", "tool:failed", "memory:added"].forEach((event) => {
    window.addEventListener(event, render);
  });

  window.MASTER_TASK_UI = Object.freeze({ ensureRail, render, task, update, tool, evidence });
  window.MasterTaskUI = window.MASTER_TASK_UI;
})();
