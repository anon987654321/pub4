# frozen_string_literal: true

# GitHub/Shopify-style baseline security headers for all pub4 Rails apps.
Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Content-Type-Options" => "nosniff",
  "X-Frame-Options" => "SAMEORIGIN",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Cross-Origin-Opener-Policy" => "same-origin",
  "X-Permitted-Cross-Domain-Policies" => "none",
  # geolocation=(self) — nearby/dating radius controllers call navigator.geolocation.
  # Blocking it with geolocation=() surfaces Permissions-Policy violations in console.
  #
  # In production this header never reaches the browser: relayd does
  # `match response header set "Permissions-Policy"`, which overwrites it for
  # every backend. Keep the two in agreement — OPENBSD/etc/relayd.conf is the
  # one that decides, and it drifted to geolocation=() for weeks, which is what
  # actually killed #nearby.
  "Permissions-Policy" => "accelerometer=(), camera=(), geolocation=(self), gyroscope=(), microphone=(), payment=(), usb=()",
  "X-XSS-Protection" => "0",
)
