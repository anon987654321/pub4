# frozen_string_literal: true

# HtmlNoStore — force no-store on HTML responses (overrides session ETag / no-cache).
class HtmlNoStore
  ASSET_PREFIX = "/assets/"
  STATIC_EXT = /\.(?:css|js|mjs|json|png|jpe?g|gif|webp|svg|ico|woff2?|map|txt)\z/i

  def initialize(app) = @app = app

  def call(env)
    status, headers, body = @app.call(env)
    return [status, headers, body] unless html_response?(env, headers)

    headers = headers.dup
    headers.delete("ETag")
    headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0, private"
    headers["Pragma"] = "no-cache"
    headers["Expires"] = "0"
    [status, headers, body]
  end

  private

  def html_response?(env, headers)
    path = env["PATH_INFO"].to_s
    return false if path.start_with?(ASSET_PREFIX)
    return false if STATIC_EXT.match?(path)

    content_type = headers["Content-Type"].to_s
    return true if content_type.include?("text/html")

    accept = env["HTTP_ACCEPT"].to_s
    path == "/" || accept.include?("text/html")
  end
end
