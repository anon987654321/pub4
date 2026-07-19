# frozen_string_literal: true

# GitHub-style baseline headers on every response (MASTER face matches fleet).
class SecurityHeaders
  HEADERS = {
    "X-Content-Type-Options" => "nosniff",
    "Referrer-Policy" => "strict-origin",
    "Permissions-Policy" => "accelerometer=(self), camera=(), geolocation=(), gyroscope=(self), microphone=(self), payment=(), usb=()",
    "X-XSS-Protection" => "0",
  }.freeze

  def initialize(app) = @app = app

  def call(env)
    status, headers, body = @app.call(env)
    headers = headers.dup
    HEADERS.each { |key, value| headers[key] = value unless headers.key?(key) }
    [status, headers, body]
  end
end