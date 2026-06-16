require 'net/http'
require 'uri'
require 'openssl'

# -----------------------------------------------------------------------------
# net-http‑0.9.1 – Minimal, safe, fully documented example
# -----------------------------------------------------------------------------
# This snippet shows the idiomatic way to perform a single HTTPS GET request
# with Ruby’s standard library. It prioritises:
#   • explicit intent
#   • deterministic error handling
#   • guaranteed resource cleanup
# -----------------------------------------------------------------------------

# 1️⃣ Build a URI – validates scheme, host and path.
uri = URI.parse('https://example.com/index.html')

# 2️⃣ Connection options – derived from the URI.
http_options = {
  use_ssl:      uri.scheme == 'https',
  open_timeout: 5,                     # seconds – fail fast on handshake timeout
  read_timeout: 5,                     # seconds – avoid indefinite blocking
  verify_mode:  OpenSSL::SSL::VERIFY_PEER
}

# 3️⃣ Perform the request inside a block.
#    Net::HTTP.start guarantees that the socket is closed even if an exception
#    bubbles out of the block.
response_body = Net::HTTP.start(uri.host, uri.port, **http_options) do |http|
  request = Net::HTTP::Get.new(uri)

  # Optional: custom headers (e.g. User‑Agent, Accept)
  # request['User-Agent'] = 'MyApp/1.0'

  begin
    response = http.request(request)

    # 4️⃣ Handle HTTP status codes explicitly.
    case response
    when Net::HTTPSuccess
      response.body
    else
      raise "HTTP #{response.code} – #{response.message}"
    end
  rescue Timeout::Error => e
    raise "Network timeout: #{e.message}"
  rescue SocketError => e
    raise "Network error: #{e.message}"
  end
end

# 5️⃣ Output – safe to pipe or log.
puts response_body
# => String containing the response body (or an exception is raised)