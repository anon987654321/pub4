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
        # Use nokogiri for safe HTML parsing
        text = extract_text(response.body)

        Result.ok(content: text[0, MAX_CONTENT_LENGTH], url: url, status: response.code)
      else
        Result.err("HTTP #{response.code} for #{url}")
      end
    rescue StandardError => e
      Result.err("Browse failed: #{e.message}")
    end

    # JavaScript-rendered pages using Ferrum (optional)
    def browse_js(url)
      require "ferrum"
      
      browser = Ferrum::Browser.new(headless: true, timeout: 30)
      browser.go_to(url)
      browser.network.wait_for_idle
      
      text = extract_text(browser.body)
      browser.quit
      
      Result.ok(content: text[0, MAX_CONTENT_LENGTH], url: url)
    rescue LoadError
      Result.err("Ferrum gem not available - install for JS-rendered pages")
    rescue StandardError => e
      Result.err("Browse JS failed: #{e.message}")
    ensure
      browser&.quit rescue nil
    end

    private

    def extract_text(html)
      require "nokogiri"
      
      doc = Nokogiri::HTML(html)
      doc.css("script, style").remove
      text = doc.text.squeeze(" \n").strip
      text
    rescue LoadError
      # Fallback to simple regex if nokogiri not available
      # WARNING: This fallback has limited ReDoS protection. Install nokogiri for production use.
      # Limit input size to prevent ReDoS
      html = html[0..50000] if html.length > 50000
      html.gsub(/<script[^>]{0,100}>.*?<\/script>/im, " ")
          .gsub(/<style[^>]{0,100}>.*?<\/style>/im, " ")
          .gsub(/<[^>]{0,200}>/, " ")
          .squeeze(" \n")
          .strip
    end
  end
end
