# frozen_string_literal: true
require "net/http"
require "uri"
require "timeout"

module Master
  module Io
    # Fetches a URL, returns first ~16KB of content with HTML stripped to plain text.
    # Rewrites well-known sites to the most useful underlying URL:
    #   github.com/.../blob/...     → raw.githubusercontent.com
    #   gist.github.com/<u>/<id>    → gist.githubusercontent.com/<u>/<id>/raw
    #   arxiv.org/abs|pdf/<id>      → ar5iv.labs.arxiv.org/html/<id>  (full text)
    #   codepen.io/<u>/pen/<slug>   → triple-fetch .html + .css + .js
    # Pairs with web_search for two-step research. Governor-permitted.
    class WebFetch
      TIER = :guarded
      NAME = "web_fetch".freeze
      DESCRIPTION = "Fetch a URL → plain text. Rewrites github/gist/arxiv/codepen URLs.".freeze
      TIMEOUT = 15
      MAX_BYTES = 16_000
      MAX_FULL_BYTES = 4 * 1024 * 1024
      # read_timeout restarts on every chunk, so a server sending a byte at a time kept a fetch
      # open for as long as it liked; this bounds the whole read.
      DEADLINE_S = 30
      Fetched = Data.define(:code, :body)
      class TooLarge < StandardError; end
      HTTP_OK = "200".freeze
      TAG_RE = /<[^>]+>/.freeze
      WS_RE = /[ \t]+/.freeze
      BLANK_RE = /\n{3,}/.freeze

      REWRITES = [
        [%r{\Ahttps://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)\z},
         'https://raw.githubusercontent.com/\1/\2/\3/\4'],
        [%r{\Ahttps://gist\.github\.com/([^/]+)/([0-9a-f]+)/?\z},
         'https://gist.githubusercontent.com/\1/\2/raw'],
        [%r{\Ahttps://arxiv\.org/(?:abs|pdf)/([\w./-]+?)(?:v\d+)?(?:\.pdf)?/?\z},
         'https://ar5iv.labs.arxiv.org/html/\1'],
      ].freeze

      CODEPEN_RE = %r{\Ahttps://codepen\.io/([^/]+)/pen/([^/?#]+)/?\z}.freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(url:, full: false)
        if (m = url.match(CODEPEN_RE))
          return fetch_codepen(m[1], m[2], full:)
        end

        rewrite(url).then { |rewritten| fetch_one(rewritten, full:) }
      end

      private

      def rewrite(url)
        REWRITES.each { |re, repl| return url.sub(re, repl) if url.match?(re) }
        url
      end

      def fetch_codepen(user, slug, full: false)
        base = "https://codepen.io/#{user}/pen/#{slug}"
        failures = []
        parts = %w[html css js].filter_map do |ext|
          result = fetch_one("#{base}.#{ext}", full:)
          if result.is_a?(Master::Result) && result.ok?
            "// #{ext}\n#{result.value!}"
          else
            failures << ext
            nil
          end
        end
        return Result.err("web_fetch: CodePen fetch failed for all components", category: :infrastructure) if parts.empty?

        note = failures.empty? ? "" : "// Unavailable CodePen components: #{failures.join(", ")}\n\n"
        Result.ok(note + parts.join("\n\n"))
      end

      def fetch_one(url, full: false)
        uri = URI(url)
        return Result.err("web_fetch: only http(s)", category: :validation) unless %w[http https].include?(uri.scheme)
        address = SsrfGuard.pinned_address(uri)
        return Result.err("web_fetch: refused internal/reserved address", category: :validation) unless address

        perm = @governor.permit?(NAME, TIER, url)
        return perm if perm.err?

        response = http_get(uri, address)
        deliver(url, response, full:)
      rescue TooLarge
        Result.err("web_fetch: response exceeds #{MAX_FULL_BYTES} bytes; narrow the request", category: :validation)
      rescue StandardError => e
        Result.err("web_fetch: #{e.message}", category: :infrastructure)
      end

      def deliver(url, response, full: false)
        return Result.err("web_fetch: HTTP #{response.code}", category: :infrastructure) unless response.code == HTTP_OK

        # BINARY from Net::HTTP; a page's non-ASCII text must reach the prompt as UTF-8.
        raw_body = String.new(response.body.to_s, encoding: Encoding::UTF_8).scrub
        stripped = strip_html(raw_body)
        stripped = stripped.byteslice(0, MAX_BYTES).scrub("") unless full
        @bus&.publish("tool:after", tool: NAME, url:)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: url)
        Result.ok(guarded(stripped, url))
      end

      # A fetched page is text from outside the tree becoming prompt, so it
      # passes Review::Security::InjectionGuard before the model sees it.
      #
      # Permissive mode on purpose: it errs only on a pattern that matched. The
      # strict mode denies anything without an allowlist token, which would
      # refuse every honest page on the web.
      def guarded(text, url) = injection_guard.screen(text, tool: NAME, source: url, bus: @bus)

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end

      def http_get(uri, address)
        http = SsrfGuard.http_for(uri, address)
        http.read_timeout = TIMEOUT
        http.open_timeout = TIMEOUT
        http.start do |h|
          h.request(Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "MASTER/1 (web_fetch)")) do |response|
            return Fetched.new(code: response.code, body: capped_body(response))
          end
        end
      end

      # Streamed, so a large page is refused at the cap rather than after it is all in memory.
      def capped_body(response)
        return "" unless response.code == HTTP_OK

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        body = +""
        response.read_body do |chunk|
          body << chunk
          raise TooLarge if body.bytesize > MAX_FULL_BYTES
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          raise Timeout::Error, "fetch exceeded #{DEADLINE_S}s" if elapsed > DEADLINE_S
        end
        body
      end

      def strip_html(body)
        body.gsub(TAG_RE, " ").gsub(WS_RE, " ").gsub(BLANK_RE, "\n\n").strip
      end
    end
  end
end
