# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "uri"

module Master
  module Io
    # Sessionful browser. Every browser request reuses WebBrowse's pinned-IP
    # transport; interaction requests require a fresh human approval.
    class BrowserAgent
      NAME = "browser_agent".freeze
      TIER = :guarded
      MAX_SESSIONS = 4
      MAX_SESSION_ID = 40
      MAX_SELECTOR = 300
      MAX_VALUE = 4_000
      SESSION_ID = /\A[A-Za-z0-9_-]{1,40}\z/.freeze
      OPERATIONS = %w[click set type].freeze

      Session = Struct.new(:browser, :page, :mutex, keyword_init: true)

      def initialize(root:, governor:, event_bus: nil, **_opts)
        @root = File.expand_path(root)
        @governor = governor
        @bus = event_bus
        @transport = WebBrowse.new(governor:, event_bus:)
        @sessions = {}
        @mutex = Mutex.new
      end

      def call(action:, session: "default", url: nil, selector: nil, value: nil,
               operation: nil, wait: 1, links: true, screenshot: false, **_opts)
        key = session_key(session)
        case action.to_s
        when "navigate" then navigate(key, url, wait:, links:, screenshot:)
        when "extract" then extract(key, links:, screenshot:)
        when "interact" then interact(key, selector, value, operation, wait:, links:, screenshot:)
        when "close" then close(key)
        else Result.err("browser_agent: unknown action: #{action}", category: :validation)
        end
      rescue ArgumentError => e
        Result.err("browser_agent: #{e.message}", category: :validation)
      rescue URI::InvalidURIError => e
        Result.err("browser_agent: invalid URL: #{e.message}", category: :validation)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "BrowserAgent")
        Result.err("browser_agent: #{e.class}: #{e.message.lines.first.to_s.strip[0, 200]}", category: :infrastructure)
      end

      private

      def session_key(value)
        key = value.to_s
        raise ArgumentError, "invalid session id" unless key.bytesize <= MAX_SESSION_ID && SESSION_ID.match?(key)

        key
      end

      def navigate(key, url, wait:, links:, screenshot:)
        uri = URI(url.to_s)
        return Result.err("browser_agent: only public http(s) URLs are allowed", category: :validation) unless web_uri?(uri)
        return Result.err("browser_agent: refused internal/reserved address", category: :validation) unless SsrfGuard.pinned_address(uri)

        permission = @governor.permit?(NAME, TIER, "navigate #{uri}")
        return permission if permission.err?

        state = open_session(key)
        state.mutex.synchronize do
          state.page.go_to(uri.to_s)
          sleep(wait.to_f.clamp(0.0, 12.0)) if wait.to_f.positive?
          render(state, links:, screenshot:)
        end
      end

      def extract(key, links:, screenshot:)
        state = lookup_session(key)
        return Result.err("browser_agent: no open session: #{key}", category: :validation) unless state

        state.mutex.synchronize { render(state, links:, screenshot:) }
      end

      def interact(key, selector, value, operation, wait:, links:, screenshot:)
        css = selector.to_s.strip
        return Result.err("browser_agent: selector is required", category: :validation) if css.empty?
        return Result.err("browser_agent: selector is too long", category: :validation) if css.bytesize > MAX_SELECTOR

        op = operation.to_s
        op = value.nil? ? "click" : "set" if op.empty?
        return Result.err("browser_agent: operation must be click, set, or type", category: :validation) unless OPERATIONS.include?(op)
        if op != "click" && (value.nil? || value.to_s.bytesize > MAX_VALUE)
          return Result.err("browser_agent: set/type requires a value of at most #{MAX_VALUE} bytes", category: :validation)
        end

        state = lookup_session(key)
        return Result.err("browser_agent: no open session: #{key}", category: :validation) unless state

        state.mutex.synchronize do
          # Governor treats this exact tool/action as a human-consent boundary;
          # automatic mode and cached "always allow" decisions cannot bypass it.
          permission = @governor.permit?(NAME, :dangerous, "interact #{op} #{state.page.url} selector=#{css}")
          return permission if permission.err?

          node = state.page.at_css(css)
          return Result.err("browser_agent: element not found: #{css}", category: :validation) unless node

          case op
          when "click" then node.click
          when "set" then node.focus.set(value.to_s)
          when "type" then node.focus.type(value.to_s)
          end
          sleep(wait.to_f.clamp(0.0, 12.0)) if wait.to_f.positive?
          render(state, links:, screenshot:)
        end
      end

      def open_session(key)
        @mutex.synchronize do
          return @sessions.fetch(key) if @sessions.key?(key)
          raise ArgumentError, "browser session limit reached (#{MAX_SESSIONS})" if @sessions.size >= MAX_SESSIONS

          browser = Ferrum::Browser.new(
            headless: true,
            timeout: WebBrowse::TIMEOUT,
            process_timeout: WebBrowse::TIMEOUT,
            browser_options: WebBrowse::BROWSER_OPTIONS,
          )
          page = browser.create_page
          @transport.secure_page(page)
          @sessions[key] = Session.new(browser:, page:, mutex: Mutex.new)
        rescue StandardError
          browser&.quit
          raise
        end
      end

      def lookup_session(key)
        @mutex.synchronize { @sessions[key] }
      end

      def close(key)
        state = @mutex.synchronize { @sessions.delete(key) }
        return Result.ok("browser session already closed: #{key}") unless state

        state.mutex.synchronize { state.browser.quit }
        Result.ok("browser session closed: #{key}")
      end

      def render(state, links:, screenshot:)
        snapshot = JSON.parse(state.page.evaluate(WebBrowse::SCRIPT))
        result = @transport.deliver_snapshot(snapshot.fetch("url", state.page.url), snapshot, links:)
        return result unless result.ok? && screenshot

        path = save_screenshot(state)
        Result.ok("#{result.value!}\n\nScreenshot saved to: #{path}")
      end

      def save_screenshot(state)
        directory = File.join(@root, ".master", "browser_screenshots")
        FileUtils.mkdir_p(directory, mode: 0o700)
        path = File.join(directory, "#{SecureRandom.hex(12)}.png")
        state.page.screenshot(path:)
        File.chmod(0o600, path)
        path
      end

      def web_uri?(uri)
        %w[http https].include?(uri.scheme.to_s.downcase) && !uri.host.to_s.empty? && uri.userinfo.nil?
      end
    end
  end
end
