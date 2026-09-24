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
    class SocialBrowser < Master::Plugin::Base
      Site = Data.define(:id, :hosts, :start_url, :composer, :submit)

      SITES = {
        "onlyfans" => Site.new(
          id: "onlyfans",
          hosts: %w[onlyfans.com],
          start_url: "https://onlyfans.com",
          composer: ["textarea", "[contenteditable='true']", "[role='textbox']"],
          submit: ["button[type='submit']", "[type='submit']", "button"]
        ),
        "fetlife" => Site.new(
          id: "fetlife",
          hosts: %w[fetlife.com],
          start_url: "https://fetlife.com",
          composer: ["textarea", "[contenteditable='true']", "[role='textbox']"],
          submit: ["button[type='submit']", "[type='submit']", "button"]
        ),
        "snapchat" => Site.new(
          id: "snapchat",
          hosts: %w[snapchat.com web.snapchat.com],
          start_url: "https://web.snapchat.com",
          composer: ["textarea", "[contenteditable='true']", "[role='textbox']"],
          submit: ["button[type='submit']", "[type='submit']", "button"]
        )
      }.freeze

      ACTIONS = %w[status inspect login publish_owned reply_inbound].freeze
      CHALLENGE_MARKERS = [
        "captcha",
        "verify you're human",
        "verify you are human",
        "unusual activity",
        "security challenge"
      ].freeze
      MAX_TEXT_BYTES = 4_000
      MAX_BODY_BYTES = 40_000
      WRITE_INTERVAL_S = 15

      def call(action:, **args)
        law_admission!
        name = action.to_s
        raise PolicyError, "#{manifest.id}: unknown action #{name}" unless ACTIONS.include?(name)

        case name
        when "status" then status
        when "inspect" then inspect_page(**args)
        when "login" then login(**args)
        when "publish_owned" then publish_owned(**args)
        when "reply_inbound" then reply_inbound(**args)
        end
      end

      private

      def status
        {
          plugin: manifest.id,
          runtime: runtime,
          browser: ferrum_available? ? "ferrum" : "unavailable",
          sites: SITES.keys.map { |id| site_status(id) }
        }
      end

      def site_status(id)
        site = site!(id)
        { id: site.id, hosts: site.hosts, start_url: site.start_url }
      end

      def inspect_page(site:, account:, url: nil, headless: true, runtime: "auto", **)
        target = url || site!(site).start_url
        with_browser(site:, account:, url: target, headless:, runtime:) do |page, run_dir|
          shot = screenshot(page, run_dir, "before")
          body = page.body.to_s.byteslice(0, MAX_BODY_BYTES).to_s
          {
            action: "inspect",
            site: site.to_s,
            runtime: runtime(),
            account: account.to_s,
            url: page.url.to_s,
            title: page.title.to_s,
            body: body,
            screenshot: shot
          }
        end
      end

      def login(site:, account:, url: nil, headless: false, runtime: "auto", **)
        target = url || site!(site).start_url
        with_browser(site:, account:, url: target, headless:, runtime:) do |page, run_dir|
          shot = screenshot(page, run_dir, "login")
          {
            action: "login",
            site: site.to_s,
            runtime: runtime(),
            account: account.to_s,
            url: page.url.to_s,
            screenshot: shot,
            note: "Complete login in the visible browser. MASTER never receives passwords, OTPs, cookies or session credentials."
          }
        end
      end

      def publish_owned(site:, account:, url:, message:, consent:, owned_account:, headless: true, runtime: "auto", selectors: {}, **)
        require_consent!(consent)
        require_policy!("account_scope", expected: "operator_owned_or_authorized")
        raise PolicyError, "social_browser: owned_account=true is required" unless owned_account == true

        write_once(site:, account:, url:, message:, headless:, runtime:, selectors:, operation: "publish_owned")
      end

      def reply_inbound(site:, account:, conversation_url:, message:, consent:, inbound:, headless: true, runtime: "auto", selectors: {}, **)
        require_consent!(consent)
        require_policy!("account_scope", expected: "operator_owned_or_authorized")
        raise PolicyError, "social_browser: inbound=true is required" unless inbound == true

        write_once(
          site:,
          account:,
          url: conversation_url,
          message:,
          headless:,
          runtime:,
          selectors:,
          operation: "reply_inbound"
        )
      end

      def write_once(site:, account:, url:, message:, headless:, runtime:, selectors:, operation:)
        validate_message!(message)
        acquire_account_lock(account) do
          enforce_write_cooldown!(account)
          with_browser(site:, account:, url:, headless:, runtime:) do |page, run_dir|
            before = screenshot(page, run_dir, "before")
            raise PolicyError, "social_browser: challenge detected; human action required" if challenge?(page)

            site = site!(site)
            composer = find_node(page, Array(selectors.fetch("composer", site.composer)))
            raise Error, "social_browser: composer not found on #{page.url}" unless composer

            composer.focus.type(message.to_s)
            typed = screenshot(page, run_dir, "typed")
            submit = find_submit(page, Array(selectors.fetch("submit", site.submit)))
            raise Error, "social_browser: submit control not found on #{page.url}" unless submit

            submit.click
            wait_for_idle(page)
            raise PolicyError, "social_browser: challenge detected after write" if challenge?(page)

            after = screenshot(page, run_dir, "after")
            record_write!(account, operation:)
            {
              action: operation,
              site: site.id,
              runtime: runtime(),
              account: account.to_s,
              url: page.url.to_s,
              screenshots: [before, typed, after],
              detail: "one explicit outbound write completed"
            }
          end
        end
      end

      def with_browser(site:, account:, url:, headless:, runtime:)
        selected = resolve_runtime(runtime)
        raise PolicyError, "social_browser: #{selected} runtime is not supported here" unless %w[macos android_termux linux openbsd].include?(selected)
        require_ferrum!
        validate_url!(site, url)
        account_name = safe_account_name(account)
        account_dir = File.join(account_root, account_name)
        run_dir = File.join(account_dir, "runs", timestamp_slug)
        FileUtils.mkdir_p(run_dir, mode: 0o700)

        browser = Ferrum::Browser.new(
          headless: headless,
          timeout: 20,
          window_size: [1280, 900],
          browser_options: { "user-data-dir" => account_dir }
        )
        page = browser.create_page
        page.go_to(url)
        yield(page, run_dir)
      rescue Ferrum::TimeoutError => e
        raise Error, "social_browser: browser timeout on #{site}: #{e.message}"
      rescue Ferrum::StatusError => e
        raise Error, "social_browser: navigation failed on #{site}: #{e.message}"
      ensure
        browser&.quit
      end

      def resolve_runtime(value)
        requested = value.to_s
        return runtime if requested.empty? || requested == "auto"
        return requested if %w[macos android_termux linux openbsd].include?(requested)

        raise PolicyError, "social_browser: runtime must be auto, macos, android_termux, linux or openbsd"
      end

      def runtime
        return "android_termux" if termux?
        host_os = RbConfig::CONFIG["host_os"].to_s.downcase
        return "openbsd" if host_os.include?("openbsd")
        return "macos" if host_os.include?("darwin")
        return "linux" if host_os.include?("linux")

        "unknown"
      end

      def termux?
        RUBY_PLATFORM.include?("android") || ENV["PREFIX"].to_s.include?("/com.termux/")
      end

      def validate_url!(id, value)
        site = site!(id)
        uri = URI(value.to_s)
        raise PolicyError, "social_browser: URL must use HTTPS" unless uri.scheme == "https"

        host = uri.host.to_s.downcase.sub(/Awww./, "")
        return if site.hosts.include?(host)

        raise PolicyError, "social_browser: host #{uri.host.inspect} is not allowed for #{site.id}"
      rescue URI::InvalidURIError => e
        raise PolicyError, "social_browser: invalid URL: #{e.message}"
      end

      def site!(id)
        SITES.fetch(id.to_s) { raise PolicyError, "social_browser: unknown site #{id}" }
      end

      def find_node(page, selectors)
        selectors.each do |selector|
          node = page.at_css(selector)
          return node if node
        rescue Ferrum::InvalidSelectorError
          next
        end
        nil
      end

      def find_submit(page, selectors)
        node = find_node(page, selectors)
        return node if node

        page.css("button").find do |button|
          button.text.to_s.strip.match?(/A(?:send|post|publish|reply)z/i)
        end
      end

      def screenshot(page, run_dir, label)
        path = File.join(run_dir, "#{label}.png")
        page.screenshot(path:, full: false)
        path
      end

      def challenge?(page)
        body = page.body.to_s.downcase
        CHALLENGE_MARKERS.any? { |marker| body.include?(marker) }
      end

      def validate_message!(message)
        text = message.to_s.strip
        raise PolicyError, "social_browser: message is empty" if text.empty?
        raise PolicyError, "social_browser: message exceeds #{MAX_TEXT_BYTES} bytes" if text.bytesize > MAX_TEXT_BYTES
      end

      def enforce_write_cooldown!(account)
        state = account_state(account)
        last = parse_time(state["last_write_at"])
        return unless last
        return if Time.now - last >= WRITE_INTERVAL_S

        raise PolicyError, "social_browser: write cooldown active for account #{account}"
      end

      def wait_for_idle(page)
        page.network.wait_for_idle(timeout: 8)
      rescue StandardError
        nil
      end

      def parse_time(value)
        text = value.to_s
        return if text.empty?

        Time.parse(text)
      rescue ArgumentError
        nil
      end

      def record_write!(account, operation:)
        path = File.join(account_root, safe_account_name(account), "state.yml")
        state = account_state(account)
        state["last_write_at"] = Time.now.utc.iso8601
        state["last_operation"] = operation
        File.write(path, YAML.dump(state), mode: "w", perm: 0o600)
      end

      def account_state(account)
        path = File.join(account_root, safe_account_name(account), "state.yml")
        File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      rescue Psych::Exception => e
        raise Error, "social_browser: invalid local state: #{e.message}"
      end

      def acquire_account_lock(account)
        dir = File.join(account_root, safe_account_name(account))
        FileUtils.mkdir_p(dir, mode: 0o700)
        File.open(File.join(dir, ".lock"), "a", 0o600) do |lock|
          locked = lock.flock(File::LOCK_EX | File::LOCK_NB)
          raise PolicyError, "social_browser: account is already in use" unless locked

          yield
        end
      end

      def account_root = File.expand_path("~/.master/plugins/social_browser/accounts")

      def safe_account_name(account)
        name = account.to_s
        raise PolicyError, "social_browser: account name is required" unless name.match?(/A[a-z0-9][a-z0-9_-]{0,63}z/i)

        name
      end

      def timestamp_slug = "#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}-#{SecureRandom.hex(4)}"

      def ferrum_available?
        require "ferrum"
        true
      rescue LoadError
        false
      end

      def require_ferrum!
        require "ferrum"
      rescue LoadError => e
        raise Error, "social_browser: ferrum is unavailable — bundle install is required: #{e.message}"
      end
    end
  end
end
