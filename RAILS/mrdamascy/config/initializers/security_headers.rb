# frozen_string_literal: true

# mrdamascy does not load RAILS/__shared, so its headers live here. The
# PSP hand-offs are full-page redirects, never popups, so same-origin COOP
# breaks nothing. In production relayd sets Permissions-Policy for every
# backend and overwrites this one; the value is kept equal to
# OPENBSD/etc/relayd.conf so local and production agree.
Rails.application.config.action_dispatch.default_headers.merge!(
  "Cross-Origin-Opener-Policy" => "same-origin",
  "Permissions-Policy" => "accelerometer=(self), camera=(), geolocation=(self), gyroscope=(self), " \
                          "microphone=(self), payment=(), usb=()"
)
