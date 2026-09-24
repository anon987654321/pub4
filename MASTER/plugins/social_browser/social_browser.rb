# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"
require "yaml"
require "uri"

module Master
  module Plugins
    class SocialBrowser < Master::Plugin::Base
      Error = Master::Plugin::Error
      PolicyError = Master::Plugin::PolicyError

      ACTIONS = %w[inspect login publish_owned reply_inbound].freeze
      DEFAULT_SELECTORS = {
        composer: [
          "textarea",
          "[contenteditable='true']",
          "[role='textbox']"
        ],
        submit: [
          "button[type='submit']",
          "[type='submit']"
        ]
      }.freeze
      CHALLENGE_MARKERS = [
        "captcha",
        "verify you're human",
        "verify you are human",
        "unusual activity",
        "security challenge"
      ].freeze
      MAX_TEXT_BYTES = 4_000
      MIN_WRITE_INTERVAL_S = 15
      MAX_BODY_BYTES = 40_000

      def call(action:, **args)
        law_admission!
        action = action.to_s
        raise PolicyError, "#{manifest.id}: unknown action #{action}" unless ACTIONS.include?(action)

        case action
        when "inspect" then inspect_page(**args)
        when "login" then login(**args)
        when "publish_owned" then publish_owned(**args)
        when "reply_inbound" then reply_inbound(**args)
        end
      end

      private

      def inspect_page(account:, url:, allowed_hosts:, headless: true, **)
        with_browser(account:, url:, allowed_hosts:, headless:) do |browser, page, run_dir|
          before = screenshot(page, run_dir, "before")
          result = page_result(page, before)
          result
        end
      end

      def login(account:, url:, allowed_hosts:, headless: false, **)
        with_browser(account:, url:, allowed_hosts:, headless:) do |browser, page, run_dir|
          screenshot_path = screenshot(page, run_dir, "login")
          {
            action: "login",
            account: account.to_s,
            url: page.url.to_s,
            screenshot: screenshot_path,
            note: "Complete login in the visible browser; MASTER never receives the password, OTP, cookie or session credential."
          }
        end
      end

      def publish_owned(account:, url:, message:, allowed_hosts:, consent:, owned_account:, selectors: {}, headless: true, **)
        require_consent!(consent)
        require_policy!("account_scope", expected: "operator_owned_or_authorized")
        raise PolicyError, "social_browser: owned_account=true is required" unless owned_account == true

        write_once(account:, url:, allowed_hosts:, headless:, selectors:, message:, operation: "publish_owned")
      end

      def reply_inbound(account:, conversation_url:, message:, allowed_hosts:, consent:, inbound:, selectors: {}, headless: true, **)
        require_consent!(consent)
        require_policy!("account_scope", expected: "operator_owned_or_authorized")
        raise PolicyError, "social_browser: inbound=true is required" unless inbound == true

        write_once(
          account:,
          url: conversation_url,
          allowed_hosts:,
          headless:,
          selectors:,
          message:,
          operation: "reply_inbound"
        )
      end

      def write_once(account:, url:, allowed_hosts:, headless:, selectors:, message:, operation:)
        validate_message!(message)
        acquire_account_lock(account) do
          enforce_write_cooldown!(account)
          with_browser(account:, url:, allowed_hosts:, headless:) do |browser, page, run_dir|
            before = screenshot(page, run_dir, "before")
            raise PolicyError, "social_browser: challenge detected; human action required" if challenge?(page)

            composer = find_node(page, Array(selectors.fetch("composer", DEFAULT_SELECTORS[:composer])))
            raise Error, "social_browser: composer not found on #{page.url}" unless composer

            composer.focus.type(message.to_s)
            typed = screenshot(page, run_dir, "typed")
            submit = find_submit(page, Array(selectors.fetch("submit", DEFAULT_SELECTORS[:submit])))
            raise Error, "social_browser: submit control not found on #{page.url}" unless submit

            submit.click
            wait_for_idle(page)
            raise PolicyError, "social_browser: challenge detected after write" if challenge?(page)

            after = screenshot(page, run_dir, "after")
            record_write!(account, operation:)
            {
              action: operation,
              account: account.to_s,
              url: page.url.to_s,
              screenshots: [before, typed, after],
              detail: "one explicit outbound write completed"
            }
          end
        end
      end

      def with_browser(account:, url:, allowed_hosts:, headless:)
        require_ferrum!
        validate_url!(url, allowed_hosts)
        account = safe_account_name(account)
        account_dir = File.join(account_root, account)
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
        yield(browser, page, run_dir)
      rescue Ferrum::TimeoutError => e
        raise Error, "social_browser: browser timeout: #{e.message}"
      rescue Ferrum::StatusError => e
        raise Error, "social_browser: navigation failed: #{e.message}"
      ensure
        browser&.quit
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
          button.text.to_s.strip.match?(/\A(?:send|post|publish|reply)\z/i)
        end
      end

      def page_result(page, screenshot_path)
        body = page.body.to_s
        body = body.byteslice(0, MAX_BODY_BYTES).to_s
        {
          action: "inspect",
          url: page.url.to_s,
          title: page.title.to_s,
          body: body,
          screenshot: screenshot_path
        }
      end

      def screenshot(page, run_dir, label)
        page.screenshot(path: File.join(run_dir, "#{label}.png"), full: false)
        File.join(run_dir, "#{label}.png")
      end

      def challenge?(page)
        body = page.body.to_s.downcase
        CHALLENGE_MARKERS.any? { |marker| body.include?(marker) }
      end

      def validate_url!(value, allowed_hosts)
        uri = URI(value.to_s)
        raise PolicyError, "social_browser: URL must use HTTPS" unless uri.scheme == "https"
        hosts = Array(allowed_hosts).map { |host| normalize_host(host) }.reject(&:empty?)
        raise PolicyError, "social_browser: allowed_hosts must be explicit" if hosts.empty?
        return if hosts.include?(normalize_host(uri.host))

        raise PolicyError, "social_browser: host #{uri.host.inspect} is not in allowed_hosts"
      rescue URI::InvalidURIError => e
        raise PolicyError, "social_browser: invalid URL: #{e.message}"
      end

      def normalize_host(host)
        host.to_s.downcase.sub(/\Awww\./, "").strip
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
        return if Time.now - last >= MIN_WRITE_INTERVAL_S

        raise PolicyError, "social_browser: write cooldown active for account #{account}"
      end

      def wait_for_idle(page)
        page.network.wait_for_idle(timeout: 8)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SocialBrowser.wait_for_idle")
      end

      def parse_time(value)
        text = value.to_s
        return if text.empty?

        Time.parse(text)
      rescue ArgumentError => e
        Master::Ground::Swallow.log(e, context: "SocialBrowser.parse_time")
        nil
      end

      def record_write!(account, operation:)
        path = File.join(account_root(safe_account_name(account)), "state.yml")
        state = account_state(account)
        state["last_write_at"] = Time.now.utc.iso8601
        state["last_operation"] = operation
        File.write(path, YAML.dump(state), mode: "w", perm: 0o600)
      end

      def account_state(account)
        path = File.join(account_root(safe_account_name(account)), "state.yml")
        File.exist?(path) ? YAML.safe_load_file(path) || {} : {}
      rescue Psych::Exception => e
        raise Error, "social_browser: invalid local state: #{e.message}"
      end

      def acquire_account_lock(account)
        dir = account_root(safe_account_name(account))
        FileUtils.mkdir_p(dir, mode: 0o700)
        lock_path = File.join(dir, ".lock")
        File.open(lock_path, "a", 0o600) do |lock|
          locked = lock.flock(File::LOCK_EX | File::LOCK_NB)
          raise PolicyError, "social_browser: account is already in use" unless locked

          yield
        end
      end

      def account_root(account = nil)
        base = File.expand_path("~/.master/plugins/social_browser/accounts")
        account ? File.join(base, safe_account_name(account)) : base
      end

      def safe_account_name(account)
        name = account.to_s
        raise PolicyError, "social_browser: account name is required" unless name.match?(/\A[a-z0-9][a-z0-9_-]{0,63}\z/i)

        name
      end

      def timestamp_slug
        "#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}-#{SecureRandom.hex(4)}"
      end

      def require_ferrum!
        require "ferrum"
      rescue LoadError => e
        raise Error, "social_browser: ferrum is unavailable — bundle install is required: #{e.message}"
      end
    end
  end
end
