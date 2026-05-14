# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Judge
  module Embeddings
    module_function

    DEFAULT_MODEL = "nomic-embed-text"
    HTTP_TIMEOUT  = 5
    MIN_SIM       = 0.30

    def enabled? = !ENV["OLLAMA_BASE_URL"].to_s.strip.empty?

    def embed(text)
      return unless enabled?
      return if text.to_s.strip.empty?
      ollama_embed(text.to_s)
    rescue StandardError
      nil
    end

    def cosine(a, b)
      return 0.0 unless a.is_a?(Array) && b.is_a?(Array) && a.size == b.size && !a.empty?
      dot, na, nb = 0.0, 0.0, 0.0
      a.each_with_index do |x, i|
        y = b[i]
        dot += x * y
        na  += x * x
        nb  += y * y
      end
      mag = Math.sqrt(na) * Math.sqrt(nb)
      mag.zero? ? 0.0 : dot / mag
    end

    def ollama_embed(text)
      uri  = URI.join(ENV["OLLAMA_BASE_URL"], "/api/embeddings")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = uri.scheme == "https"
      http.read_timeout = HTTP_TIMEOUT
      http.open_timeout = HTTP_TIMEOUT
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      req.body = JSON.generate(model: ENV.fetch("EMBEDDINGS_MODEL", DEFAULT_MODEL), prompt: text)
      res = http.request(req)
      return unless res.is_a?(Net::HTTPSuccess)
      vec = JSON.parse(res.body)["embedding"]
      vec.is_a?(Array) ? vec : nil
    end
  end
  end
end
