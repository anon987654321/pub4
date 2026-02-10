# frozen_string_literal: true

require "net/http"
require "uri"

module MASTER
  # Web - Browse and fetch web content
  module Web
    extend self

    MAX_CONTENT_LENGTH = 5000

    def browse(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(Net::HTTP::Get.new(uri))

      if response.code.start_with?("2")
        # Simple text extraction - remove scripts, styles, and HTML tags
        # Using conservative patterns to avoid ReDoS vulnerabilities
        text = response.body.dup
        
        # Remove script blocks (limit backtracking)
        while (match = text.match(/<script(?:\s[^>]{0,200})?>|<script>/i))
          start_pos = match.begin(0)
          end_pos = text.index(/<\/script>/i, start_pos)
          if end_pos
            text[start_pos..(end_pos + 8)] = " "
          else
            text[start_pos..-1] = " "
            break
          end
        end
        
        # Remove style blocks (limit backtracking)
        while (match = text.match(/<style(?:\s[^>]{0,200})?>|<style>/i))
          start_pos = match.begin(0)
          end_pos = text.index(/<\/style>/i, start_pos)
          if end_pos
            text[start_pos..(end_pos + 7)] = " "
          else
            text[start_pos..-1] = " "
            break
          end
        end
        
        # Remove all remaining HTML tags with limited backtracking
        text.gsub!(/<[^<>]*>/, " ")
        
        # Normalize whitespace
        text.gsub!(/\s+/, " ")
        text.strip!

        Result.ok(content: text[0, MAX_CONTENT_LENGTH], url: url, status: response.code)
      else
        Result.err("HTTP #{response.code} for #{url}")
      end
    rescue StandardError => e
      Result.err("Browse failed: #{e.message}")
    end
  end
end
