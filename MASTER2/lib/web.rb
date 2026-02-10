# frozen_string_literal: true

require "net/http"
require "uri"

module MASTER
  # Web - Browse and fetch web content
  module Web
    extend self

    def browse(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(Net::HTTP::Get.new(uri))

      if response.code.start_with?("2")
        # Strip HTML tags for simple text extraction
        text = response.body
          .gsub(/<script[^>]*>.*?<\/script>/mi, "")
          .gsub(/<style[^>]*>.*?<\/style>/mi, "")
          .gsub(/<[^>]+>/, " ")
          .gsub(/\s+/, " ")
          .strip

        Result.ok(content: text[0, 5000], url: url, status: response.code)
      else
        Result.err("HTTP #{response.code} for #{url}")
      end
    rescue StandardError => e
      Result.err("Browse failed: #{e.message}")
    end
  end
end
