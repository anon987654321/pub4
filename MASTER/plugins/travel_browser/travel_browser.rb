# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "time"
require "uri"

module Master
  module Plugins
    class TravelBrowser < Master::Plugin::Base
      PolicyError = Master::Plugin::PolicyError

      ACTIONS = %w[status inspect open login fill click book].freeze
      SENSITIVE_FIELD = /password|passcode|otp|one.?time|cvv|cvc|security.?code|card|credit|debit|passport/i
      CHALLENGE_MARKERS = [
        "captcha",
        "verify you're human",
        "verify you are human",
        "security challenge",
        "unusual activity",
        "access denied",
      ].freeze
      MAX_BODY_BYTES = 40_000
      MAX_TEXT_BYTES = 4_000

      def initialize(...)
        super
        @browsers = {}
      end

      def call(action:, **args)
        law_admission!
        name = action.to_s
        raise PolicyError, "#{manifest.id}: unknown action #{name}" unless ACTIONS.include?(name)

        case name
        when "status" then status
        when "inspect" then inspect_page(**args)
        when "open" then open(**args)
        when "login" then login(**args)
        when "fill" then fill(**args)
        when "click" then click(**args)
        when "book" then book(**args)
        end
      end

      private

      def status
        {
          plugin: manifest.id,
          runtime: runtime,
          browser: ferrum_available? ? "ferrum" : "unavailable",
          sessions: Dir.glob(File.join(session_root, "*")).select { |p| File.directory?(p) }.map { |p| File.basename(p) }.sort,
          final_purchase_gate: true,
          sensitive_fields_manual: true,
        }
      end

      def inspect_page(session:, **)
        with_browser(session:, headless: false) do |page, run_dir|
          {
            action: "inspect",
            session: session.to_s,
            url: page.url.to_s,
            title: page.title.to_s,
            body: guarded_page_text(page.body.to_s.byteslice(0, MAX_BODY_BYTES).to_s, page.url.to_s),
            forms: page.css("input, select, textarea, button").first(120).map { |node| describe_node(node) },
            screenshot: screenshot(page, run_dir, "inspect"),
          }
        end
      end

      def open(session:, url:, headless: false, **)
        validate_url!(url)
        with_browser(session:, headless:) do |page, run_dir|
          page.go_to(url.to_s)
          wait_for_idle(page)
          stop_on_challenge!(page)
          {
            action: "open",
            session: session.to_s,
            url: page.url.to_s,
            title: page.title.to_s,
            screenshot: screenshot(page, run_dir, "open"),
          }
        end
      end

      def login(session:, wait_seconds: 300, **)
        with_browser(session:, headless: false) do |page, run_dir|
          stop_on_challenge!(page)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds.to_i.clamp(10, 900)
          loop do
            sleep 2
            stop_on_challenge!(page)
            break if login_complete?(page)
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          end
          {
            action: "login",
            session: session.to_s,
            url: page.url.to_s,
            title: page.title.to_s,
            screenshot: screenshot(page, run_dir, "login"),
            note: "Enter credentials and one-time codes yourself in this visible browser. MASTER does not receive or store them.",
          }
        end
      end

      def login_complete?(page)
        fields = page.css("input").map do |node|
          [node.attribute("type").to_s, node.attribute("name").to_s, node.attribute("autocomplete").to_s]
        end
        !fields.any? { |type, name, autocomplete| [type, name, autocomplete].join(" ").match?(SENSITIVE_FIELD) }
      rescue StandardError
        false
      end

      def fill(session:, selector:, value:, **)
        raise PolicyError, "travel_browser: sensitive fields must be entered manually" if sensitive_selector?(selector)
        validate_fill_value!(value)

        with_browser(session:, headless: false) do |page, run_dir|
          stop_on_challenge!(page)
          node = page.at_css(selector.to_s)
          raise PolicyError, "travel_browser: selector not found: #{selector}" unless node

          node.focus.type(value.to_s)
          {
            action: "fill",
            session: session.to_s,
            selector: selector.to_s,
            url: page.url.to_s,
            screenshot: screenshot(page, run_dir, "filled"),
          }
        end
      end

      def click(session:, selector:, **)
        with_browser(session:, headless: false) do |page, run_dir|
          stop_on_challenge!(page)
          node = page.at_css(selector.to_s)
          raise PolicyError, "travel_browser: selector not found: #{selector}" unless node
          node.click
          wait_for_idle(page)
          stop_on_challenge!(page)

          {
            action: "click",
            session: session.to_s,
            selector: selector.to_s,
            url: page.url.to_s,
            title: page.title.to_s,
            screenshot: screenshot(page, run_dir, "clicked"),
          }
        end
      end

      def book(session:, selector:, confirm_purchase:, expected_total: nil, **)
        unless confirm_purchase == true
          raise PolicyError, "travel_browser: final purchase requires confirm_purchase=true"
        end

        with_browser(session:, headless: false) do |page, run_dir|
          stop_on_challenge!(page)
          body = guarded_page_text(page.body.to_s.byteslice(0, MAX_BODY_BYTES).to_s, page.url.to_s)
          total = extract_total(body)
          if expected_total && total && normalize_money(total) != normalize_money(expected_total)
            raise PolicyError, "travel_browser: visible total #{total.inspect} does not match expected #{expected_total.inspect}"
          end

          before = screenshot(page, run_dir, "purchase-before")
          node = page.at_css(selector.to_s)
          raise PolicyError, "travel_browser: final purchase selector not found: #{selector}" unless node

          node.click
          wait_for_idle(page)
          stop_on_challenge!(page)
          after = screenshot(page, run_dir, "purchase-after")

          {
            action: "book",
            session: session.to_s,
            url: page.url.to_s,
            title: page.title.to_s,
            visible_total: extract_total(page.body.to_s),
            screenshots: [before, after],
            note: "Browser submission completed; confirmation must be verified from the resulting page or booking email.",
          }
        end
      end

      def with_browser(session:, headless:)
        require_ferrum!
        name = safe_session_name(session)
        dir = File.join(session_root, name)
        run_dir = File.join(dir, "runs", timestamp_slug)
        FileUtils.mkdir_p(run_dir, mode: 0o700)

        browser = Ferrum::Browser.new(
          headless:,
          timeout: 30,
          window_size: [1440, 1000],
          browser_options: { "user-data-dir" => dir },
        )
        page = browser.create_page
        yield(page, run_dir)
      rescue Ferrum::TimeoutError => e
        raise Error, "travel_browser: browser timeout: #{e.message}"
      rescue Ferrum::StatusError => e
        raise Error, "travel_browser: browser navigation failed: #{e.message}"
      ensure
        browser&.quit
      end

      def validate_url!(value)
        uri = URI(value.to_s)
        raise PolicyError, "travel_browser: URL must use HTTPS" unless uri.scheme == "https"
        raise PolicyError, "travel_browser: URL must have a host" if uri.host.to_s.empty?
        return if Master::Io::SsrfGuard.safe_uri?(uri)

        raise PolicyError, "travel_browser: destination is not a public routable address"
      rescue URI::InvalidURIError => e
        raise PolicyError, "travel_browser: invalid URL: #{e.message}"
      end

      def stop_on_challenge!(page)
        body = page.body.to_s.downcase
        return unless CHALLENGE_MARKERS.any? { |marker| body.include?(marker) }

        raise PolicyError, "travel_browser: security challenge detected; human action required"
      end

      def guarded_page_text(text, url)
        Master::Review::Security::InjectionGuard.new(mode: :permissive).screen(
          text,
          tool: "travel_browser",
          source: url,
        )
      end

      def describe_node(node)
        {
          tag: node.tag_name.to_s,
          type: node.attribute("type").to_s,
          name: node.attribute("name").to_s,
          id: node.attribute("id").to_s,
          placeholder: node.attribute("placeholder").to_s,
          text: node.text.to_s.strip[0, 160],
        }
      rescue StandardError
        {}
      end

      def sensitive_selector?(selector)
        selector.to_s.match?(SENSITIVE_FIELD)
      end

      def validate_fill_value!(value)
        text = value.to_s
        raise PolicyError, "travel_browser: fill value is empty" if text.empty?
        raise PolicyError, "travel_browser: fill value exceeds #{MAX_TEXT_BYTES} bytes" if text.bytesize > MAX_TEXT_BYTES
      end

      def extract_total(text)
        matches = text.to_s.scan(/(?:total|grand total|amount due|price)[^\n]{0,100}?((?:[A-Z]{3}|[$€£])\s?[0-9][0-9,]*(?:\.[0-9]{2})?)/i)
        matches.flatten.first
      end

      def normalize_money(value)
        value.to_s.gsub(/\s+/, "").upcase
      end

      def screenshot(page, run_dir, label)
        path = File.join(run_dir, "#{label}.png")
        page.screenshot(path:, full: false)
        path
      end

      def wait_for_idle(page)
        page.network.wait_for_idle(timeout: 10)
      rescue StandardError
        nil
      end

      def safe_session_name(value)
        name = value.to_s
        raise PolicyError, "travel_browser: session name is required" unless name.match?(/\A[a-z0-9][a-z0-9_-]{0,63}\z/i)
        name
      end

      def session_root
        path = File.expand_path("~/.master/plugins/travel_browser/sessions")
        FileUtils.mkdir_p(path, mode: 0o700)
        path
      end

      def timestamp_slug = Time.now.utc.strftime("%Y%m%dT%H%M%S")

      def runtime
        return "android_termux" if RUBY_PLATFORM.include?("android") || ENV["PREFIX"].to_s.include?("/com.termux/")
        host_os = RbConfig::CONFIG["host_os"].to_s.downcase
        return "openbsd" if host_os.include?("openbsd")
        return "macos" if host_os.include?("darwin")
        return "linux" if host_os.include?("linux")
        "unknown"
      end

      def ferrum_available?
        require "ferrum"
        true
      rescue LoadError
        false
      end

      def require_ferrum!
        require "ferrum"
      rescue LoadError => e
        raise Error, "travel_browser: ferrum is unavailable — bundle install is required: #{e.message}"
      end
    end
  end
end
