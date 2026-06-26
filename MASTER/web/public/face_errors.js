"use strict";

function faceLogWarn(context, err, extra) {
  console.warn(`[${context}]`, err, extra ?? "");
}

function faceLogError(context, err) {
  const msg = err?.message || String(err || context);
  console.error(`[${context}]`, err);
  const el = document.getElementById("error-live");
  if (el && msg) el.textContent = `${context}: ${msg}`;
}

window.MASTER_LOG = {
  warn: faceLogWarn,
  error: faceLogError
};