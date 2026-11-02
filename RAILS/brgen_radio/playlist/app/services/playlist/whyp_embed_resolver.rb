# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "timeout"
require "uri"

module Playlist
  # Resolve Whyp share URLs during explicit import/refresh. Rendering reads the
  # stored URL and never performs network work.
  class WhypEmbedResolver
    ENDPOINT = URI("https://api.whyp.it/api/oembed").freeze
    SOURCE_HOSTS = %w[whyp.it www.whyp.it].freeze
    EMBED_HOST = "whyp.it"
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 4
    MAX_RESPONSE_BYTES = 65_536

    def initialize(request: nil)
      @request = request || method(:fetch)
    end

    def call(source_url)
      source = validated_source(source_url)
      return unless source

      endpoint = ENDPOINT.dup
      endpoint.query = URI.encode_www_form(format: "json", url: source.to_s)
      response = @request.call(endpoint)
      return unless response.respond_to?(:code) && response.code.to_i == 200

      body = response.body.to_s
      return if body.empty? || body.bytesize > MAX_RESPONSE_BYTES

      data = JSON.parse(body)
      return unless data.is_a?(Hash) && data["type"] == "rich"

      embed = iframe_url(data["html"])
      return unless valid_embed?(embed)

      preserve_share_parameters(embed, source).to_s
    rescue JSON::ParserError, URI::InvalidURIError, ArgumentError, IOError,
           SystemCallError, Timeout::Error
      nil
    end

    private

    def validated_source(value)
      raw = value.to_s
      return if raw.empty? || raw.bytesize > 2_048

      uri = URI.parse(raw)
      return unless uri.scheme == "https"
      return unless SOURCE_HOSTS.include?(uri.host.to_s.downcase)
      return if uri.userinfo || uri.port != 443 || uri.fragment
      return unless uri.path.match?(%r{\A/tracks/[^/]+\z})

      uri
    end

    def fetch(endpoint)
      Net::HTTP.start(
        endpoint.host,
        endpoint.port,
        use_ssl: true,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
      ) do |http|
        http.get(endpoint.request_uri, "Accept" => "application/json")
      end
    end

    def iframe_url(html)
      return unless html.is_a?(String) && html.bytesize <= MAX_RESPONSE_BYTES

      match = html.match(/<iframe\b[^>]*\bsrc\s*=\s*(["'])(.*?)\1/i)
      return unless match

      URI.parse(CGI.unescapeHTML(match[2]))
    end

    def valid_embed?(uri)
      uri.is_a?(URI::HTTPS) &&
        uri.host.to_s.downcase == EMBED_HOST &&
        uri.port == 443 &&
        uri.userinfo.nil? &&
        uri.path.match?(%r{\A/embeds/track/[A-Za-z0-9_-]+\z})
    end

    def preserve_share_parameters(embed, source)
      query = URI.decode_www_form(embed.query.to_s).to_h
      share = URI.decode_www_form(source.query.to_s).to_h
      %w[token in].each do |key|
        query[key] = share[key] if share.key?(key)
      end
      embed.query = URI.encode_www_form(query) unless query.empty?
      embed
    end
  end
end
