# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Review
    module Embeddings
      module_function

      DEFAULT_MODEL = "nomic-embed-text"
      HTTP_TIMEOUT = 5
      MIN_SIM = 0.30

      @ollama_alive = nil

      def enabled? = !ENV["OLLAMA_BASE_URL"].to_s.strip.empty? && ollama_alive?

      def embed(text)
        return unless enabled?
        text_str = text.to_s
        return if text_str.strip.empty?
        ollama_embed(text_str)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "embeddings.embed")
        nil
      end

      def ollama_alive?
        return @ollama_alive unless @ollama_alive.nil?
        uri = URI.join(ENV["OLLAMA_BASE_URL"], "/api/tags")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = HTTP_TIMEOUT
        http.read_timeout = HTTP_TIMEOUT
        res = http.get(uri.request_uri)
        @ollama_alive = res.is_a?(Net::HTTPSuccess)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Embeddings.ollama_alive?")
        @ollama_alive = false
      end

      def cosine(a, b)
        return 0.0 unless a.is_a?(Array) && b.is_a?(Array) && a.size == b.size && !a.empty?
        dot, na, nb = 0.0, 0.0, 0.0
        a.each_with_index do |x, i|
          y = b[i]
          dot += x * y
          na += x * x
          nb += y * y
        end
        mag = Math.sqrt(na) * Math.sqrt(nb)
        mag.zero? ? 0.0 : dot / mag
      end

      def ollama_embed(text)
        uri = URI.join(ENV["OLLAMA_BASE_URL"], "/api/embeddings")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = HTTP_TIMEOUT
        http.open_timeout = HTTP_TIMEOUT
        req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
        req.body = JSON.generate(model: ENV.fetch("EMBEDDINGS_MODEL", DEFAULT_MODEL), prompt: text)
        res = http.request(req)
        return unless res.is_a?(Net::HTTPSuccess)
        parsed = begin
          JSON.parse(res.body)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Embeddings.ollama_embed")
          nil
        end
        vec = parsed&.fetch("embedding", nil)
        vec.is_a?(Array) ? vec : nil
      end
    end
  end
end
