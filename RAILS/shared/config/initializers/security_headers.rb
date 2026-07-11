# frozen_string_literal: true

# GitHub/Shopify-style baseline security headers for all pub4 Rails apps.
Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Content-Type-Options" => "nosniff",
  "X-Frame-Options" => "SAMEORIGIN",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Cross-Origin-Opener-Policy" => "same-origin",
  "X-Permitted-Cross-Domain-Policies" => "none",
  "Permissions-Policy" => "accelerometer=(), camera=(), geolocation=(), gyroscope=(), microphone=(), payment=(), usb=()",
  "X-XSS-Protection" => "0"
)