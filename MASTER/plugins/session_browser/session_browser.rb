# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "securerandom"
require "time"
require "uri"
require "yaml"

module Master
  module Plugins
    class SessionBrowser < Master::Plugin::Base
      Error = Master::Plugin::Error
      PolicyError = Master::Plugin::PolicyError

      ACTIONS = %w[status inspect open login extract look follow paginate close].freeze
      MAX_SESSIONS = 4
      MAX_URL_BYTES = 2_000
      MAX_SELECTOR_BYTES = 300
      MAX_WAIT_SECONDS = 12
      MAX_LOGIN_HOLD_SECONDS = 900
      MAX_CAPTURE_FILES = 500
      MAX_PAGINATION_PAGES = 50
      MAX_PAGINATION_OUTPUT_BYTES = 128 * 1024
      SESSION_NAME = /\A[a-z0-9][a-z0-9_-]{0,39}\z/i.freeze
      SENSITIVE_QUERY_KEY = /(?:token|secret|password|passwd|credential|auth|session|otp|one.?time|signature|jwt|api.?key|access.?key|code)/i.freeze
      DEFAULT_NEXT_SELECTORS = [
        "a[rel='next']",
        "a[aria-label*='Next' i]",
        "a[aria-label*='Neste' i]",
        ".pagination a.next",
        "a.next",
      ].freeze

      class ReadGovernor
        def permit?(*) = Master::Result.ok(true)
      end

      def call(action:, session: "default", url: nil, selector: nil, wait: 1,
               links: true, max_pages: 10, hold_s: MAX_LOGIN_HOLD_SECONDS, **_opts)
        law_admission!
        name = action.to_s
        raise PolicyError, "session_browser: unknown action #{name.inspect}" unless ACTIONS.include?(name)

        key = session_name(session)
        case name
        when "status" then status
        when "inspect" then inspect_page(key, url:, wait:, links:)
        when "open" then open_page(key, url:, wait:)
        when "login" then login(key, url:, wait:, hold_s:)
        when "extract" then extract(key, links:)
        when "look" then look(key)
        when "follow" then follow(key, selector:, wait:, links:)
        when "paginate" then paginate(key, selector:, max_pages:, wait:, links:)
        when "close" then close_session(key)
        end
      end

      private

      def status
        hosts = allowed_hosts
        {
          plugin: manifest.id,
          browser: ferrum_available? ? "ferrum" : "unavailable",
          policy: hosts.empty? ? "blocked: no allowed hosts configured" : "host allowlist active",
          allowed_hosts: hosts,
          max_sessions: MAX_SESSIONS,
          persisted_state: true,
          read_only_transport: true,
        }
      end

      def inspect_page(key, url:, wait:, links:)
        uri = validate_url!(url)
        with_session(key, initial_url: uri) do |directory, state|
          with_browser(directory, state.fetch("host"), headless: true) do |page|
            navigate(page, uri)
            quiet_settle(page, wait)
            snapshot = snapshot_for(page)
            state["url"] = persisted_url(snapshot.fetch("url", page.url.to_s))
            state["updated_at"] = Time.now.utc.iso8601
            write_state(directory, state)
            {
              action: "inspect",
              session: key,
              url: snapshot["url"],
              title: snapshot["title"].to_s,
              body: extract_text(snapshot, links:),
              screenshot: capture(page, key),
            }
          end
        end
      end

      def open_page(key, url:, wait:)
        uri = validate_url!(url)
        with_session(key, initial_url: uri) do |directory, state|
          with_browser(directory, state.fetch("host"), headless: true) do |page|
            navigate(page, uri)
            quiet_settle(page, wait)
            snapshot = snapshot_for(page)
            state["url"] = persisted_url(snapshot.fetch("url", page.url.to_s))
            state["updated_at"] = Time.now.utc.iso8601
            write_state(directory, state)
            {
              action: "open",
              session: key,
              url: snapshot["url"],
              title: snapshot["title"].to_s,
              screenshot: capture(page, key),
              note: "Read-only navigation only. Form submissions and mutating HTTP methods are blocked.",
            }
          end
        end
      end

      def login(key, url:, wait:, hold_s:)
        unless display_available?
          raise PolicyError, "session_browser: visible login requires a workstation display; run MASTER on the desktop or use an authorized existing browser profile"
        end

        uri = validate_url!(url)
        with_session(key, initial_url: uri) do |directory, state|
          with_browser(directory, state.fetch("host"), headless: false) do |page|
            navigate(page, uri)
            quiet_settle(page, wait)
            state["url"] = persisted_url(page.url.to_s)
            state["updated_at"] = Time.now.utc.iso8601
            write_state(directory, state)
            screenshot = capture(page, key)
            wait_for_operator(page, hold_s)
            {
              action: "login",
              session: key,
              url: state["url"],
              screenshot:,
              note: "The visible window is operator-controlled. MASTER never reads passwords or OTPs. POST-based login submissions are blocked by the read-only transport; use only a compatible GET-based sign-in flow or an already-authorized browser profile.",
            }
          end
        end
      end

      def extract(key, links:)
        with_session(key) do |directory, state|
          url = state.fetch("url") { raise PolicyError, "session_browser: session has no saved URL; open a page first" }
          uri = validate_bound_url!(url, state)
          with_browser(directory, state.fetch("host"), headless: true) do |page|
            navigate(page, uri)
            snapshot = snapshot_for(page)
            state["url"] = persisted_url(snapshot.fetch("url", page.url.to_s))
            state["updated_at"] = Time.now.utc.iso8601
            write_state(directory, state)
            {
              action: "extract",
              session: key,
              url: snapshot["url"],
              title: snapshot["title"].to_s,
              body: extract_text(snapshot, links:),
            }
          end
        end
      end

      # A screenshot is evidence only. This action cannot click, follow, submit, or navigate.
      def look(key)
        with_session(key) do |directory, state|
          url = state.fetch("url") { raise PolicyError, "session_browser: session has no saved URL; open a page first" }
          uri = validate_bound_url!(url, state)
          with_browser(directory, state.fetch("host"), headless: true) do |page|
            navigate(page, uri)
            {
              action: "look",
              session: key,
              url: page.url.to_s,
              screenshot: capture(page, key),
              note: "Visual evidence only; no browser action was inferred from the screenshot.",
            }
          end
        end
      end

      # Follow literal hrefs with navigation, never by triggering page click handlers.
      def follow(key, selector:, wait:, links:)
        css = require_selector!(selector)
        with_session(key) do |directory, state|
          url = state.fetch("url") { raise PolicyError, "session_browser: session has no saved URL; open a page first" }
          current = validate_bound_url!(url, state)
          with_browser(directory, state.fetch("host"), headless: true) do |page|
            navigate(page, current)
            node = page.at_css(css)
            raise PolicyError, "session_browser: anchor not found: #{css}" unless node

            target = readonly_anchor_target!(page, node, css, state)
            navigate(page, target)
            quiet_settle(page, wait)
            snapshot = snapshot_for(page)
            state["url"] = persisted_url(snapshot.fetch("url", page.url.to_s))
            state["updated_at"] = Time.now.utc.iso8601
            write_state(directory, state)
            {
              action: "follow",
              session: key,
              url: snapshot["url"],
              title: snapshot["title"].to_s,
              body: extract_text(snapshot, links:),
            }
          end
        end
      end

      def paginate(key, selector:, max_pages:, wait:, links:)
        css = selector.to_s.strip
        css = DEFAULT_NEXT_SELECTORS.join(", ") if css.empty?
        css = require_selector!(css)
        limit = Integer(max_pages).clamp(1, MAX_PAGINATION_PAGES)

        with_session(key) do |directory, state|
          url = state.fetch("url") { raise PolicyError, "session_browser: session has no saved URL; open a page first" }
          current = validate_bound_url!(url, state)
          with_browser(directory, state.fetch("host"), headless: true) do |page|
            pages = []
            bytes = 0
            truncated = false

            limit.times do
              navigate(page, current)
              snapshot = snapshot_for(page)
              body = extract_text(snapshot, links:)
              if bytes + body.bytesize > MAX_PAGINATION_OUTPUT_BYTES
                truncated = true
                break
              end
              pages << body
              bytes += body.bytesize

              node = page.at_css(css)
              break unless node

              current = readonly_anchor_target!(page, node, css, state)
              quiet_settle(page, wait)
            end

            state["url"] = persisted_url(page.url.to_s)
            state["updated_at"] = Time.now.utc.iso8601
            write_state(directory, state)
            {
              action: "paginate",
              session: key,
              pages: pages.length,
              truncated:,
              body: pages.each_with_index.map { |body, i| "Page #{i + 1}\n#{body}" }.join("\n\n---\n\n"),
            }
          end
        end
      rescue ArgumentError => e
        raise PolicyError, "session_browser: invalid pagination limit: #{e.message}"
      end

      def close_session(key)
        directory = session_directory(key)
        with_global_lock do
          raise PolicyError, "session_browser: unknown session #{key}" unless File.file?(state_path(directory))

          with_session_file_lock(directory) do
            state = read_state(directory)
            state["active"] = false
            state["url"] = nil
            state["updated_at"] = Time.now.utc.iso8601
            write_state(directory, state)
          end
        end
        {
          action: "close",
          session: key,
          closed: true,
          note: "The route and active-session slot were cleared. The owner-only Chromium profile remains on disk; remove the session directory locally to erase its cookies and site data.",
        }
      end

      def with_session(key, initial_url: nil)
        initial = initial_url && validate_url!(initial_url)
        reserve_session!(key, initial)
        directory = session_directory(key)
        with_session_file_lock(directory) do
          state = read_state(directory)
          raise PolicyError, "session_browser: session is closed; open it again" unless state["active"] == true
          raise PolicyError, "session_browser: session state has no host binding" if state["host"].to_s.empty?
          if state["url"] && canonical_host(URI(state["url"]).host) != state["host"]
            raise PolicyError, "session_browser: saved URL host disagrees with the session binding"
          end
          if initial && canonical_host(initial.host) != state["host"]
            raise PolicyError, "session_browser: session is bound to #{state["host"]}; refused #{initial.host}"
          end
          yield directory, state
        end
      end

      def reserve_session!(key, initial_uri)
        directory = session_directory(key)
        with_global_lock do
          state = File.file?(state_path(directory)) ? read_state(directory) : nil
          raise PolicyError, "session_browser: open requires a URL" if state.nil? && initial_uri.nil?

          requested_host = initial_uri && canonical_host(initial_uri.host)
          if state && !state["host"].to_s.empty? && requested_host && state["host"] != requested_host
            raise PolicyError, "session_browser: session is bound to #{state["host"]}; refused #{requested_host}"
          end
          if state && state["active"] != true && initial_uri.nil?
            raise PolicyError, "session_browser: session is closed; open it again with a URL"
          end

          state ||= { "id" => key, "host" => requested_host, "url" => nil, "active" => false }
          if state["active"] != true
            raise PolicyError, "session_browser: session limit reached (#{MAX_SESSIONS})" if active_session_count >= MAX_SESSIONS
            state["active"] = true
          end
          state["host"] ||= requested_host
          state["updated_at"] = Time.now.utc.iso8601
          write_state(directory, state)
        end
      end

      def active_session_count
        Dir.glob(File.join(session_root, "*", "state.yml")).count do |path|
          state = YAML.safe_load_file(path, aliases: false)
          state.is_a?(Hash) && state["active"] == true
        rescue Psych::Exception => e
          raise PolicyError, "session_browser: cannot trust session inventory: #{e.message}"
        end
      end

      def with_browser(directory, host, headless:)
        require_ferrum!
        profile = File.join(directory, "profile")
        secure_directory(profile)
        options = Master::Io::WebBrowse::BROWSER_OPTIONS.merge("user-data-dir" => profile)
        browser = Ferrum::Browser.new(
          headless:,
          timeout: Master::Io::WebBrowse::TIMEOUT,
          process_timeout: Master::Io::WebBrowse::TIMEOUT,
          browser_options: options,
        )
        page = browser.create_page
        transport.secure_page(page, allowed_host: host)
        yield page
      ensure
        browser&.quit
      end

      def navigate(page, uri)
        transport.reset_page_budget(page)
        page.go_to(uri.to_s)
        page
      end

      def quiet_settle(page, wait)
        seconds = Float(wait).clamp(0.0, MAX_WAIT_SECONDS)
        page.network.wait_for_idle(timeout: [seconds, 1.0].max)
      rescue StandardError
        # Loading state can be unavailable for long-polling sites; the result remains bounded.
        nil
      end

      def snapshot_for(page)
        JSON.parse(page.evaluate(Master::Io::WebBrowse::SCRIPT))
      rescue JSON::ParserError => e
        raise Error, "session_browser: page snapshot was not valid JSON: #{e.message}"
      end

      def extract_text(snapshot, links:)
        result = transport.deliver_snapshot(snapshot.fetch("url", ""), snapshot, links:)
        raise Error, "session_browser: page extraction failed: #{result.message}" unless result.ok?

        result.value!.to_s
      end

      def readonly_anchor_target!(page, node, selector, state)
        unless node.tag_name.to_s.downcase == "a" && !node.attribute("href").to_s.strip.empty?
          raise PolicyError, "session_browser: #{selector.inspect} is not an anchor with href; scripted-only flows are unsupported"
        end

        target = URI.join(page.url.to_s, node.attribute("href").to_s)
        validate_bound_url!(target.to_s, state)
      rescue URI::InvalidURIError => e
        raise PolicyError, "session_browser: invalid anchor target: #{e.message}"
      end

      def validate_bound_url!(raw, state)
        uri = validate_url!(raw)
        unless canonical_host(uri.host) == state.fetch("host")
          raise PolicyError, "session_browser: session is bound to #{state.fetch("host")}; refused #{uri.host}"
        end
        uri
      end

      def validate_url!(raw)
        value = raw.to_s
        raise PolicyError, "session_browser: URL required" if value.strip.empty?
        raise PolicyError, "session_browser: URL exceeds #{MAX_URL_BYTES} bytes" if value.bytesize > MAX_URL_BYTES

        uri = URI(value)
        unless %w[http https].include?(uri.scheme.to_s.downcase) && !uri.host.to_s.empty? && uri.userinfo.nil?
          raise PolicyError, "session_browser: only public HTTP(S) URLs without embedded credentials are allowed"
        end
        require_allowed_host!(uri.host)
        unless Master::Io::SsrfGuard.pinned_address(uri)
          raise PolicyError, "session_browser: refused internal or reserved destination"
        end
        uri
      rescue URI::InvalidURIError => e
        raise PolicyError, "session_browser: invalid URL: #{e.message}"
      end

      def require_allowed_host!(host)
        hosts = allowed_hosts
        raise PolicyError, "session_browser: no allowed_hosts are configured in data/laws.yml" if hosts.empty?
        return if hosts.include?(canonical_host(host))

        raise PolicyError, "session_browser: host #{host.inspect} is not in data/laws.yml plugins.session_browser.allowed_hosts"
      end

      def allowed_hosts
        list = policy.fetch("allowed_hosts", [])
        raise PolicyError, "session_browser: allowed_hosts policy must be an array" unless list.is_a?(Array)

        list.map do |host|
          value = host.to_s.strip
          labels = value.split(".")
          valid = !value.empty? && labels.all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/i) }
          raise PolicyError, "session_browser: invalid host in allowlist" unless valid

          canonical_host(value)
        end.uniq.sort
      end

      def canonical_host(host)
        host.to_s.downcase.sub(/\.\z/, "").sub(/\Awww\./, "")
      end

      def session_name(value)
        name = value.to_s
        raise PolicyError, "session_browser: invalid session name" unless name.match?(SESSION_NAME)

        name
      end

      def require_selector!(raw)
        css = raw.to_s.strip
        raise PolicyError, "session_browser: selector required" if css.empty?
        raise PolicyError, "session_browser: selector exceeds #{MAX_SELECTOR_BYTES} bytes" if css.bytesize > MAX_SELECTOR_BYTES

        css
      end

      def display_available?
        host = RbConfig::CONFIG["host_os"].to_s.downcase
        return true if host.include?("darwin")

        !ENV["DISPLAY"].to_s.empty? || !ENV["WAYLAND_DISPLAY"].to_s.empty?
      end

      def wait_for_operator(page, hold_s)
        hold = Integer(hold_s).clamp(0, MAX_LOGIN_HOLD_SECONDS)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + hold
        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          sleep 2
          begin
            page.current_url
          rescue StandardError
            break
          end
        end
      end

      def capture(page, key)
        directory = capture_directory
        File.open(File.join(directory, ".lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          raise PolicyError, "session_browser: capture inventory is busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          path = File.join(directory, "#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}_#{key}_#{SecureRandom.hex(5)}.png")
          page.screenshot(path:, full: false)
          File.chmod(0o600, path)
          prune_captures!(directory)
          path
        end
      end

      def prune_captures!(directory)
        files = Dir.glob(File.join(directory, "*.png")).sort_by { |path| File.mtime(path) }
        files.first([files.size - MAX_CAPTURE_FILES, 0].max).each do |path|
          File.delete(path)
        rescue SystemCallError
          nil
        end
      end

      def persist_url(raw)
        uri = URI(raw.to_s)
        if uri.query
          pairs = URI.decode_www_form(uri.query)
          safe = pairs.reject { |key, _value| key.match?(SENSITIVE_QUERY_KEY) }
          uri.query = safe.empty? ? nil : URI.encode_www_form(safe)
        end
        uri.fragment = nil if uri.fragment.to_s.match?(SENSITIVE_QUERY_KEY)
        uri.to_s
      rescue URI::InvalidURIError, ArgumentError
        raise PolicyError, "session_browser: refusing to persist an invalid or ambiguous URL"
      end
      alias persisted_url persist_url

      def read_state(directory)
        path = state_path(directory)
        state = YAML.safe_load_file(path, aliases: false)
        raise PolicyError, "session_browser: invalid local state" unless state.is_a?(Hash)
        raise PolicyError, "session_browser: local state has the wrong session id" unless state["id"] == File.basename(directory)
        state
      rescue Psych::Exception => e
        raise PolicyError, "session_browser: invalid local state: #{e.message}"
      end

      def write_state(directory, state)
        secure_directory(directory)
        path = state_path(directory)
        temporary = "#{path}.#{Process.pid}.#{SecureRandom.hex(5)}.tmp"
        File.write(temporary, YAML.dump(state), mode: "w", perm: 0o600)
        File.chmod(0o600, temporary)
        File.rename(temporary, path)
        File.chmod(0o600, path)
      ensure
        File.delete(temporary) if temporary && File.exist?(temporary)
      end

      def with_session_file_lock(directory)
        secure_directory(directory)
        File.open(File.join(directory, ".lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          raise PolicyError, "session_browser: session is already in use" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          yield
        end
      end

      def with_global_lock
        directory = session_root
        File.open(File.join(directory, ".sessions.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          raise PolicyError, "session_browser: session inventory is busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          yield
        end
      end

      def session_root
        secure_directory(File.join(Dir.home, ".master", "plugins", "session_browser", "sessions"))
      end

      def session_directory(key)
        secure_directory(File.join(session_root, key))
      end

      def state_path(directory) = File.join(directory, "state.yml")

      def capture_directory
        secure_directory(File.join(Dir.home, ".master", "plugins", "session_browser", "captures"))
      end

      def secure_directory(path)
        FileUtils.mkdir_p(path, mode: 0o700)
        File.chmod(0o700, path)
        path
      end

      def transport
        @transport ||= Master::Io::WebBrowse.new(governor: ReadGovernor.new)
      end

      def ferrum_available?
        return true if defined?(Ferrum::Browser)

        require "ferrum"
        true
      rescue LoadError
        false
      end

      def require_ferrum!
        return if defined?(Ferrum::Browser)

        require "ferrum"
      rescue LoadError => e
        raise Error, "session_browser: Ferrum is unavailable; install MASTER's declared dependencies: #{e.message}"
      end
    end
  end
end
