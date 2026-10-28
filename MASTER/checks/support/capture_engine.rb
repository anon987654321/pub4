# frozen_string_literal: true

require "json"
require_relative "cdp_session"
require_relative "stress_scripts"

module Deploy
  # One interface for the browsers a surface is captured in. A session needs
  # six verbs: open, close, viewport, navigate, evaluate, screenshot. Computed
  # styles and box geometry are built on evaluate here, so every engine answers
  # them with the same script and a difference between engines is a difference
  # in the page, not in the probe.
  #
  # MASTER_VISUAL_ENGINES lists the engines (default chrome; webkit and firefox
  # are opt-in). An engine that is not installed, or refuses automation, is
  # skipped with a recorded reason rather than failing the pass.
  module CaptureEngine
    # Raised by an engine that cannot run here; the message is the note.
    class Unavailable < StandardError; end

    GEOMETRY_JS = <<~'JS'.sub("__PATH__") { StressScripts::PATH_JS }.freeze
      (() => {
        __PATH__
        const rows = [];
        for (const el of document.body.querySelectorAll("*")) {
          if (rows.length >= 400) break;
          if (/^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|SVG|PATH|BR)$/i.test(el.tagName)) continue;
          const r = el.getBoundingClientRect();
          if (r.width < 2 || r.height < 2 || getComputedStyle(el).display === "none") continue;
          rows.push({ key: path(el), x: Math.round(r.left + scrollX), y: Math.round(r.top + scrollY), w: Math.round(r.width), h: Math.round(r.height) });
        }
        return { width: document.documentElement.clientWidth, scroll_width: document.documentElement.scrollWidth,
                 scroll_height: document.documentElement.scrollHeight, rows };
      })()
    JS

    STYLES_JS = <<~'JS'.freeze
      ((selector, props) => {
        const el = document.querySelector(selector);
        if (!el) return null;
        const s = getComputedStyle(el);
        return Object.fromEntries(props.map((p) => [p, s.getPropertyValue(p)]));
      })(__SELECTOR__, __PROPS__)
    JS

    @unavailable = {}

    class << self
      attr_reader :unavailable

      def registry = (@registry ||= { "chrome" => :chrome, "webkit" => :webkit, "firefox" => :firefox })

      # Names from MASTER_VISUAL_ENGINES, chrome first, unknown names dropped.
      def requested(env = ENV)
        names = env.fetch("MASTER_VISUAL_ENGINES", "chrome").split(/[,\s]+/).map(&:downcase).reject(&:empty?)
        (["chrome"] + names).uniq & registry.keys
      end

      def others(env = ENV) = requested(env) - ["chrome"]

      # An opened engine, or nil with the reason recorded in `unavailable`.
      # A failed engine is not retried within the run.
      def open(name, host_map: {}, factory: nil)
        return if @unavailable.key?(name)

        engine = (factory || method(:build)).call(name, host_map:)
        engine.open
        engine
      rescue Unavailable, CdpSession::Error, SystemCallError, IOError => e
        @unavailable[name] = e.message.to_s[0, 160]
        nil
      end

      def reset! = @unavailable = {}

      def build(name, host_map: {})
        case name
        when "chrome" then ChromeEngine.new(host_map:)
        when "webkit" then WebDriverEngine.safari
        when "firefox" then WebDriverEngine.firefox
        else raise Unavailable, "unknown engine #{name}"
        end
      end
    end

    # The verbs a subclass supplies; everything else is defined on them.
    class Base
      attr_reader :name

      def geometry = evaluate(GEOMETRY_JS)

      def styles(selector, props)
        evaluate(STYLES_JS.sub("__SELECTOR__") { selector.to_json }.sub("__PROPS__") { props.to_json })
      end

      def open = raise(NotImplementedError)
      def close = raise(NotImplementedError)
      def viewport(_width, _height, mobile: false) = raise(NotImplementedError)
      def navigate(_url) = raise(NotImplementedError)
      def evaluate(_js) = raise(NotImplementedError)
      def screenshot(_path) = raise(NotImplementedError)
    end

    # Chrome through the CDP client the pass already holds, or its own.
    class ChromeEngine < Base
      def self.wrap(cdp) = new(cdp:)

      def initialize(cdp: nil, host_map: {})
        @name = "chrome"
        @cdp = cdp
        @host_map = host_map
        @owned = cdp.nil?
      end

      def open
        return self unless @owned

        @cdp = CdpSession.new(host_map: @host_map)
        @cdp.start
        self
      end

      def close = (@owned ? @cdp&.close : nil)
      def viewport(width, height, mobile: false) = @cdp.viewport(width, height, mobile:)
      def navigate(url) = @cdp.navigate(url)
      def evaluate(js) = @cdp.evaluate(js)
      def screenshot(path) = @cdp.screenshot(path, capture_beyond_viewport: true)
    end
  end
end

require_relative "webdriver_engine"
