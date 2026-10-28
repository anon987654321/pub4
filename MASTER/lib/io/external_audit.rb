# frozen_string_literal: true

require "net/http"
require "uri"
require "timeout"
require_relative "ssrf_guard"

module Master
  module Io
    # Passive external website assessment. Never authenticates, submits forms or
    # performs exploit probes. Missing headers are review prompts, not confirmed bugs.
    class ExternalAudit
      NAME = "external_audit".freeze
      TIER = :guarded
      DESCRIPTION = "Passively assess public website headers and observable HTML semantics.".freeze
      TIMEOUT = 10
      MAX_REDIRECTS = 3
      MAX_BODY_BYTES = 1_048_576
      HTML_TYPES = /text\/html|application\/xhtml\+xml/i.freeze
      class ResponseTooLarge < StandardError; end

      SECURITY_HEADERS = {
        "Content-Security-Policy" => "Review CSP against the application's needs",
        "X-Content-Type-Options" => "Review MIME-sniffing protection",
        "Referrer-Policy" => "Review referrer data disclosure",
        "Permissions-Policy" => "Review browser-feature access policy",
      }.freeze

      def initialize(governor:, event_bus: nil, browser: nil)
        @governor = governor
        @bus = event_bus
        @browser = browser
      end

      def call(url:, render: false)
        uri = parse_url(url)
        return uri if uri.is_a?(Master::Result)
        return Result.err("external_audit: render must be boolean", category: :validation) unless [true, false].include?(render)

        permit = @governor.permit?(NAME, TIER, { url: uri.to_s, mode: "passive", render: })
        return permit if permit.err?
        fetched = fetch_page(uri)
        return fetched if fetched.is_a?(Master::Result)

        response, final_uri, redirects, body = fetched
        body = response.body.to_s if body.nil?
        headers = response.each_header.to_h.transform_keys(&:downcase)
        lines = [
          "MASTER external website assessment",
          "Initial URL: #{uri}",
          "Final URL: #{final_uri}",
          "HTTP status: #{response.code}",
          "Redirects followed: #{redirects}",
          "Mode: passive GET only; no credentials, form submissions or exploit probes",
          "TLS: #{final_uri.scheme == 'https' ? 'HTTPS handshake completed with standard certificate verification' : 'HTTP only; transport is not encrypted'}",
          header_observation(headers, "strict-transport-security", final_uri.scheme == "https" ? "HSTS" : nil),
          *SECURITY_HEADERS.map { |name, _note| header_observation(headers, name.downcase, name) },
          frame_policy(headers),
          "", "Observable HTML and UX signals"
        ]
        if !headers.fetch("content-type", "").match?(HTML_TYPES)
          lines << "HTML structure: NOT APPLICABLE (response is not identified as HTML)"
        else
          lines.concat(html_observations(body))
        end

        if render
          return Result.err("external_audit: rendered-browser lane unavailable", category: :infrastructure) unless @browser
          navigation = @browser.call(action: "navigate", session: "external-assessment", url: final_uri.to_s, wait: 2, links: false)
          lines << ""
          if navigation.ok?
            screenshot = @browser.call(action: "look", session: "external-assessment")
            lines << (screenshot.ok? ? "Rendered evidence: #{screenshot.value!}" : "Rendered evidence: INCONCLUSIVE (#{screenshot.message})")
            lines << "Visual judgement requires the configured vision lane to inspect the screenshot."
          else
            lines << "Rendered evidence: INCONCLUSIVE (#{navigation.message})"
          end
        end

        lines << ""
        lines << "Limit: observable signals only; this is not a source audit or penetration-test certification."
        @bus&.publish("tool:after", tool: NAME, url: final_uri.to_s, status: response.code.to_i, render:)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: final_uri.to_s)
        Result.ok(lines.join("\n"))
      rescue StandardError => e
        Result.err("external_audit: #{e.class}: #{e.message}", category: :infrastructure)
      end

      private

      def parse_url(raw)
        text = raw.to_s.strip
        return Result.err("external_audit: URL required (maximum 2048 bytes)", category: :validation) if text.empty? || text.bytesize > 2_048

        uri = URI.parse(text)
        return Result.err("external_audit: only HTTP(S) URLs", category: :validation) unless %w[http https].include?(uri.scheme)
        return Result.err("external_audit: embedded credentials forbidden", category: :validation) if uri.user || uri.password
        return Result.err("external_audit: hostname required", category: :validation) if uri.host.to_s.empty?
        uri.fragment = nil
        uri
      rescue URI::InvalidURIError => e
        Result.err("external_audit: invalid URL: #{e.message}", category: :validation)
      end

      def fetch_page(start_uri)
        current = start_uri
        redirects = 0
        loop do
          address = SsrfGuard.pinned_address(current)
          return Result.err("external_audit: refused internal/reserved destination", category: :policy) unless address
          http = SsrfGuard.http_for(current, address, timeout: TIMEOUT)
          body = +""
          response = Timeout.timeout(TIMEOUT * 3) do
            http.start do |client|
            request = Net::HTTP::Get.new(current.request_uri)
            request["User-Agent"] = "MASTER/1 (passive external assessment)"
            request["Accept"] = "text/html,application/xhtml+xml,*/*;q=0.1"
            client.request(request) do |incoming|
              incoming.read_body do |chunk|
                raise ResponseTooLarge if body.bytesize + chunk.bytesize > MAX_BODY_BYTES
                body << chunk
              end
            end
            end
          end
          if response.is_a?(Net::HTTPRedirection)
            return Result.err("external_audit: redirect limit exceeded", category: :validation) if redirects >= MAX_REDIRECTS
            location = response["location"]
            return Result.err("external_audit: redirect lacks location", category: :validation) if location.to_s.empty?
            next_uri = URI.join(current.to_s, location)
            return Result.err("external_audit: redirect changes host; assess new host separately", category: :policy) unless next_uri.host.to_s.casecmp(current.host.to_s).zero?
            return Result.err("external_audit: redirect destination must be HTTP(S)", category: :validation) unless %w[http https].include?(next_uri.scheme)
            return Result.err("external_audit: redirect credentials forbidden", category: :validation) if next_uri.user || next_uri.password
            current = next_uri
            redirects += 1
            next
          end
          return [response, current, redirects, body]
        end
      rescue ResponseTooLarge
        Result.err("external_audit: response body exceeds #{MAX_BODY_BYTES} bytes", category: :validation)
      rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
        Result.err("external_audit: TIMEOUT (#{e.class})", category: :timeout)
      rescue StandardError => e
        Result.err("external_audit: fetch failed: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def header_observation(headers, key, label)
        return "#{label || key}: NOT APPLICABLE" if label.nil?
        value = headers[key].to_s.strip
        return "#{label}: PRESENT (#{value[0, 220]})" unless value.empty?
        "#{label}: REVIEW (header absent; absence alone does not confirm a vulnerability)"
      end

      def frame_policy(headers)
        return "Framing protection: PRESENT via CSP frame-ancestors" if headers["content-security-policy"].to_s.match?(/(?:^|;)\s*frame-ancestors\b/i)
        return "Framing protection: PRESENT via X-Frame-Options" unless headers["x-frame-options"].to_s.empty?
        "Framing protection: REVIEW (no observed CSP frame-ancestors or X-Frame-Options)"
      end

      def html_observations(html)
        images = html.scan(/<img\b[^>]*>/im)
        missing_alt = images.count { |tag| !tag.match?(/\balt\s*=/i) }
        title = html.match(/<title\b[^>]*>(.*?)<\/title\s*>/im)&.captures&.first.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
        lang = html.match(/<html\b[^>]*\blang\s*=\s*['"]?([^\s'">]+)/i)&.captures&.first
        h1 = html.scan(/<h1\b/i).size
        [
          "Document title: #{title.empty? ? 'REVIEW (missing or empty)' : "PRESENT (#{title[0, 140]})"}",
          "HTML language: #{lang ? "PRESENT (#{lang})" : 'REVIEW (lang attribute not observed)'}",
          "Viewport meta: #{html.match?(/<meta\b[^>]*name\s*=\s*['"]viewport['"]/i) ? 'PRESENT' : 'REVIEW (not observed)'}",
          "H1 count: #{h1} (heuristic; count alone is not a verdict)",
          "Semantic landmarks: main=#{html.match?(/<main\b/i)}, nav=#{html.match?(/<nav\b/i)}",
          "Images: #{images.size} observed, #{missing_alt} without alt attribute (decorative images may use alt=\"\")",
          "Links with href: #{html.scan(/<a\b[^>]*href\s*=/i).size}",
          "Forms: #{html.scan(/<form\b/i).size}; password input fields: #{html.scan(/<input\b[^>]*type\s*=\s*['"]?password/i).size} (not an auth-security test)",
        ]
      end
    end
  end
end
