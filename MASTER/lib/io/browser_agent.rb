# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "uri"

begin
  require "ferrum"
rescue LoadError
  # The rest of MASTER can boot without Chrome's driver; browser actions report
  # the missing capability when called rather than taking down the whole boot.
end

module Master
  module Io
    # Sessionful, read-oriented browser. WebBrowse owns the pinned-IP transport,
    # SSRF checks, GET/HEAD-only policy, network sandbox and request budgets.
    # A session is bound to the host that opened it. Interactive controls remain
    # a separate authority boundary and require fresh human approval.
    class BrowserAgent
      NAME = "browser".freeze
      TIER = :guarded
      MAX_SESSIONS = 4
      MAX_SESSION_ID = 40
      MAX_SELECTOR = 300
      MAX_VALUE = 4_000
      MAX_CAPTURES = 500
      MAX_PAGINATION_OUTPUT_BYTES = 128 * 1024
      SESSION_ID = /\A[A-Za-z0-9_-]{1,40}\z/.freeze
      OPERATIONS = %w[click set type].freeze
      DEFAULT_NEXT_SELECTORS = [
        "a[rel='next']",
        "a[aria-label*='Next' i]",
        "a[aria-label*='Neste' i]",
        ".pagination a.next",
        "a.next",
      ].freeze

      Session = Struct.new(:browser, :page, :mutex, :host, :headless, keyword_init: true)

      def initialize(root:, governor:, event_bus: nil, **_opts)
        @root = File.expand_path(root)
        @governor = governor
        @bus = event_bus
        @transport = WebBrowse.new(governor:, event_bus:)
        @sessions = {}
        @mutex = Mutex.new
        @capture_mutex = Mutex.new
      end

      def call(action:, session: "default", url: nil, selector: nil, value: nil,
               operation: nil, wait: 1, links: true, max_pages: 10, **_opts)
        key = session_key(session)
        case action.to_s
        when "status"   then status
        when "navigate" then navigate(key, url, wait:, links:)
        when "login"    then login(key, url, wait:, links:)
        when "extract"  then extract(key, links:)
        when "look"     then look(key)
        when "follow"   then follow(key, selector, wait:, links:)
        when "paginate" then paginate(key, selector, max_pages:, wait:, links:)
        when "interact" then interact(key, selector, value, operation, wait:, links:)
        when "close"    then close(key)
        else Result.err("browser: unknown action: #{action}", category: :validation)
        end
      rescue ArgumentError => e
        Result.err("browser_agent: #{e.message}", category: :validation)
      rescue URI::InvalidURIError => e
        Result.err("browser_agent: invalid URL: #{e.message}", category: :validation)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Browser")
        Result.err("browser_agent: #{e.class}: #{e.message.lines.first.to_s.strip[0, 200]}", category: :infrastructure)
      end

      private

      def status
        rows = @mutex.synchronize do
          @sessions.sort.map { |key, state| "#{key}=#{state.host} (#{state.headless ? "headless" : "visible"})" }
        end
        Result.ok("browser ready; runtime=#{ferrum_available? ? "ferrum" : "unavailable"}; " \
                   "sessions=#{rows.empty? ? "none" : rows.join(", ")}")
      end

      def session_key(value)
        key = value.to_s
        raise ArgumentError, "invalid session id" unless key.bytesize <= MAX_SESSION_ID && SESSION_ID.match?(key)

        key
      end

      def navigate(key, raw_url, wait:, links:)
        uri = public_uri!(raw_url)
        permission = @governor.permit?(NAME, TIER, "navigate #{uri}")
        return permission if permission.err?

        state = open_session(key, host: uri.host, headless: headless_for_navigation(key))
        state.mutex.synchronize do
          ensure_session_host!(state, uri)
          @transport.reset_page_budget(state.page)
          state.page.go_to(uri.to_s)
          settle(wait)
          render(state, links:)
        end
      end

      # The operator completes sign-in inside a visible browser window.
      # MASTER never receives a password or one-time code; cookies remain in
      # Chromium's live session and disappear when that browser closes.
      def login(key, raw_url, wait:, links:)
        uri = public_uri!(raw_url)
        permission = @governor.permit?(NAME, TIER, "open visible login browser at #{uri.host}")
        return permission if permission.err?

        state = open_session(key, host: uri.host, headless: false)
        state.mutex.synchronize do
          ensure_session_host!(state, uri)
          @transport.reset_page_budget(state.page)
          state.page.go_to(uri.to_s)
          settle(wait)
          result = render(state, links:)
          return result unless result.ok?

          Result.ok("#{result.value!}\n\nVisible browser opened for operator-controlled sign-in. " \
                    "Credentials stay outside MASTER, but this session permits only GET/HEAD requests, " \
                    "so ordinary POST-based login submissions are blocked. The session is bound to #{state.host}.")
        end
      end

      def extract(key, links:)
        state = lookup_session(key)
        return Result.err("browser_agent: no open session: #{key}", category: :validation) unless state

        state.mutex.synchronize { render(state, links:) }
      end

      # Capture the current viewport without reading or re-extracting the DOM.
      # A caller may pass this path to a vision lane for description; the
      # caption never becomes a navigation command.
      def look(key)
        state = lookup_session(key)
        return Result.err("browser_agent: no open session: #{key}", category: :validation) unless state

        state.mutex.synchronize do
          path = save_screenshot(state)
          Result.ok("URL: #{state.page.url}\nScreenshot saved to: #{path}\n" \
                    "The capture is visual evidence only; it does not drive browser actions.")
        end
      end

      # Follow a literal href, not a model-selected click target. Navigating to
      # the href avoids firing arbitrary page click handlers; the transport still
      # refuses cross-host requests and any non-GET/HEAD method.
      def follow(key, raw_selector, wait:, links:)
        selector = require_selector!(raw_selector)
        state = lookup_session(key)
        return Result.err("browser_agent: no open session: #{key}", category: :validation) unless state

        state.mutex.synchronize do
          node = state.page.at_css(selector)
          return Result.err("browser_agent: element not found: #{selector}", category: :validation) unless node

          target = target_from_anchor!(state, node, selector)
          permission = @governor.permit?(NAME, TIER, "follow #{target}")
          return permission if permission.err?

          @transport.reset_page_budget(state.page)
          state.page.go_to(target.to_s)
          settle(wait)
          render(state, links:)
        end
      end

      def paginate(key, raw_selector, max_pages:, wait:, links:)
        selector = raw_selector.to_s.strip
        selector = DEFAULT_NEXT_SELECTORS.join(", ") if selector.empty?
        selector = require_selector!(selector)
        limit = Integer(max_pages).clamp(1, 50)
        state = lookup_session(key)
        return Result.err("browser_agent: no open session: #{key}", category: :validation) unless state

        pages = []
        output_bytes = 0
        output_limited = false
        state.mutex.synchronize do
          limit.times do
            result = render(state, links:)
            return result unless result.ok?

            page_text = result.value!.to_s
            if output_bytes + page_text.bytesize > MAX_PAGINATION_OUTPUT_BYTES
              output_limited = true
              break
            end
            pages << page_text
            output_bytes += page_text.bytesize
            break if pages.size >= limit

            node = state.page.at_css(selector)
            break unless node

            target = target_from_anchor!(state, node, selector)
            permission = @governor.permit?(NAME, TIER, "paginate #{target}")
            return permission if permission.err?

            @transport.reset_page_budget(state.page)
            state.page.go_to(target.to_s)
            settle(wait)
          end
        end
        note = output_limited ? " (stopped at #{MAX_PAGINATION_OUTPUT_BYTES} byte output limit)" : ""
        body = pages.each_with_index.map { |page, index| "Page #{index + 1}\n#{page}" }.join("\n\n---\n\n")
        Result.ok("paginated #{pages.size} page(s)#{note}\n\n#{body}")
      end

      def interact(key, raw_selector, value, operation, wait:, links:)
        selector = require_selector!(raw_selector)
        op = operation.to_s
        op = value.nil? ? "click" : "set" if op.empty?
        return Result.err("browser_agent: operation must be click, set, or type", category: :validation) unless OPERATIONS.include?(op)
        if op != "click" && (value.nil? || value.to_s.bytesize > MAX_VALUE)
          return Result.err("browser_agent: set/type requires a value of at most #{MAX_VALUE} bytes", category: :validation)
        end

        state = lookup_session(key)
        return Result.err("browser_agent: no open session: #{key}", category: :validation) unless state

        state.mutex.synchronize do
          node = state.page.at_css(selector)
          return Result.err("browser_agent: element not found: #{selector}", category: :validation) unless node

          # Clicking an anchor is reduced to its same-host href. Other controls
          # still use Ferrum, but every such interaction gets fresh approval and
          # the transport refuses POST/PUT/PATCH/DELETE and off-host requests.
          target = target_from_anchor!(state, node, selector) if op == "click" && anchor?(node)
          label = [node.text, node.attribute("aria-label"), node.attribute("title"),
                   node.attribute("name"), node.attribute("type")].compact.map(&:to_s)
            .map { |part| part.gsub(/[[:cntrl:]]/, " ").gsub(/\s+/, " ").strip }
            .find { |part| !part.empty? }.to_s[0, 100]
          sensitive = node.attribute("type").to_s.casecmp("password").zero? ||
                      node.attribute("name").to_s.match?(/password|token|secret|credential|otp|auth|verification|code/i)
          preview = if op == "click"
                      ""
                    else
                      text = sensitive ? "[redacted]" : value.to_s.gsub(/[[:cntrl:]]/, " ")[0, 120].inspect
                      " value=#{text}"
                    end
          page_url = URI(state.page.url)
          page_url.query = nil
          page_url.fragment = nil
          description = "interact #{op} #{page_url} selector=#{selector} target=#{label.inspect}#{preview}"
          permission = @governor.permit?(NAME, :dangerous, description)
          return permission if permission.err?

          @transport.reset_page_budget(state.page)
          if target
            state.page.go_to(target.to_s)
          else
            case op
            when "click" then node.click
            when "set" then node.focus.set(value.to_s)
            when "type" then node.focus.type(value.to_s)
            end
          end
          settle(wait)
          render(state, links:)
        end
      end

      def open_session(key, host:, headless:)
        @mutex.synchronize do
          if (existing = @sessions[key])
            unless existing.host.casecmp(host.to_s).zero?
              raise ArgumentError, "session #{key} is bound to #{existing.host}; close it before opening another host"
            end
            unless existing.headless == headless
              mode = existing.headless ? "headless" : "visible"
              raise ArgumentError, "session #{key} is already #{mode}; close it before changing browser mode"
            end

            return existing
          end
          raise ArgumentError, "browser session limit reached (#{MAX_SESSIONS})" if @sessions.size >= MAX_SESSIONS

          ferrum!
          browser = Ferrum::Browser.new(
            headless:,
            timeout: WebBrowse::TIMEOUT,
            process_timeout: WebBrowse::TIMEOUT,
            browser_options: WebBrowse::BROWSER_OPTIONS,
          )
          page = browser.create_page
          @transport.secure_page(page, allowed_host: host.to_s.downcase)
          @sessions[key] = Session.new(browser:, page:, mutex: Mutex.new, host: host.to_s.downcase, headless:)
        rescue StandardError
          browser&.quit
          raise
        end
      end

      def ferrum!
        return if defined?(Ferrum::Browser)

        require "ferrum"
      rescue LoadError
        raise ArgumentError, "Ferrum is not installed; install MASTER's declared dependencies to use browser actions"
      end

      def ferrum_available?
        return true if defined?(Ferrum::Browser)

        require "ferrum"
        true
      rescue LoadError
        false
      end

      def lookup_session(key)
        @mutex.synchronize { @sessions[key] }
      end

      # Once the operator has signed in through a visible window, explicit
      # navigation reuses that window rather than silently trying to replace it
      # with a headless session. A new session remains headless by default.
      def headless_for_navigation(key)
        state = lookup_session(key)
        state.nil? ? true : state.headless
      end

      def close(key)
        state = @mutex.synchronize { @sessions.delete(key) }
        return Result.ok("browser session already closed: #{key}") unless state

        state.mutex.synchronize { state.browser.quit }
        Result.ok("browser session closed: #{key}")
      end

      def render(state, links:)
        snapshot = JSON.parse(state.page.evaluate(WebBrowse::SCRIPT))
        result = @transport.deliver_snapshot(snapshot.fetch("url", state.page.url), snapshot, links:)
        return result unless result.ok?

        path = save_screenshot(state)
        Result.ok("#{result.value!}\n\nScreenshot saved to: #{path}")
      end

      def save_screenshot(state)
        directory = File.join(Dir.home, ".master", "plugins", "session_browser", "captures")
        @capture_mutex.synchronize do
          FileUtils.mkdir_p(directory, mode: 0o700)
          File.chmod(0o700, directory)
          stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S")
          path = File.join(directory, "#{stamp}_#{SecureRandom.hex(8)}.png")
          state.page.screenshot(path:)
          File.chmod(0o600, path)
          prune_screenshots!(directory)
          path
        end
      end

      def prune_screenshots!(directory)
        files = Dir.glob(File.join(directory, "*.png"))
        return if files.size <= MAX_CAPTURES

        files.sort_by { |file| File.mtime(file) }.first(files.size - MAX_CAPTURES).each do |file|
          File.delete(file)
        rescue StandardError
          nil
        end
      end

      def public_uri!(raw)
        raise ArgumentError, "url required" if raw.to_s.strip.empty?
        raise ArgumentError, "url too long" if raw.to_s.bytesize > 2_000

        uri = URI(raw.to_s)
        raise ArgumentError, "only public http(s) URLs without embedded credentials are allowed" unless web_uri?(uri)
        raise ArgumentError, "refused internal/reserved address" unless SsrfGuard.pinned_address(uri)

        uri
      end

      def ensure_session_host!(state, uri)
        raise ArgumentError, "only public http(s) URLs are allowed" unless web_uri?(uri)
        return true if uri.host.to_s.casecmp(state.host.to_s).zero?

        raise ArgumentError, "session is bound to #{state.host}; refused navigation to #{uri.host}"
      end

      def target_from_anchor!(state, node, selector)
        unless anchor?(node)
          raise ArgumentError, "selector #{selector.inspect} is not an <a href>; form controls are not followed"
        end

        target = URI.join(state.page.url.to_s, node.attribute("href").to_s)
        ensure_session_host!(state, target)
        raise ArgumentError, "refused internal/reserved address" unless SsrfGuard.pinned_address(target)

        target
      end

      def anchor?(node)
        node.tag_name.to_s.downcase == "a" && !node.attribute("href").to_s.strip.empty?
      end

      def require_selector!(raw)
        selector = raw.to_s.strip
        raise ArgumentError, "selector required" if selector.empty?
        raise ArgumentError, "selector too long" if selector.bytesize > MAX_SELECTOR

        selector
      end

      def settle(wait)
        seconds = Float(wait).clamp(0.0, 12.0)
        sleep(seconds) if seconds.positive?
      end

      def web_uri?(uri)
        %w[http https].include?(uri.scheme.to_s.downcase) &&
          !uri.host.to_s.empty? && uri.userinfo.nil?
      end
    end
  end
end
