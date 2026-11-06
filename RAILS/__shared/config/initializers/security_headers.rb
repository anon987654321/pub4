# frozen_string_literal: true

require_relative "../../lib/shared/cross_origin_resource_policy"

# GitHub/Shopify-style baseline security headers for all pub4 Rails apps.
Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Content-Type-Options" => "nosniff",
  "X-Frame-Options" => "SAMEORIGIN",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Cross-Origin-Opener-Policy" => "same-origin",
  # same-origin for pages and JSON; Shared::CrossOriginResourcePolicy relaxes it
  # to cross-origin for images and Active Storage files, which webmail and the
  # other city domains embed.
  "Cross-Origin-Resource-Policy" => "same-origin",
  "X-Permitted-Cross-Domain-Policies" => "none",
  # geolocation=(self) — nearby/dating radius controllers call navigator.geolocation.
  # accelerometer/gyroscope=(self) — MASTER's face (tilt + shake) and RAILS
  # parallax-tilt on phones. Blocking them here while relayd allows (self) meant
  # local and production disagreed the same way geolocation=() killed #nearby.
  # browsing-topics=() — no page here asks the browser for ad topics, so none
  # is offered to the third parties a page embeds.
  #
  # In production this header never reaches the browser: relayd does
  # `match response header set "Permissions-Policy"`, which overwrites it for
  # every backend. Keep the two in agreement — OPENBSD/etc/relayd.conf is the
  # one that decides.
  "Permissions-Policy" => "accelerometer=(self), browsing-topics=(), camera=(), geolocation=(self), gyroscope=(self), microphone=(self), payment=(), usb=()",
  "X-XSS-Protection" => "0",
)

Rails.application.config.middleware.use Shared::CrossOriginResourcePolicy
