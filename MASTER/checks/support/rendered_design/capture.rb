# frozen_string_literal: true

require "uri"
require "yaml"
require_relative "../rendered_design"

module Deploy
  module RenderedDesign
    # One snapshot of a page for the design-book Laws, measured through a CdpSession that is
    # already open: every width mobile first, then the desktop, with the chrome scrolled,
    # focus walked, spacing raised, pseudo-states forced, fonts resolved, motion watched and
    # transfer bytes summed at the first width only, because those cost seconds.
    module Capture
      PROBES = File.expand_path("../geometry_probe", __dir__)
      PROBE = %w[design_laws design_laws_motion].map { |name| File.read(File.join(PROBES, "#{name}.js")) }.freeze
      HEIGHTS = { 390 => 844, 360 => 780, 320 => 640, 1280 => 800 }.freeze
      BUDGETS = File.expand_path("../../data/page_weight.yml", __dir__)

      TABS = 30
      FORCED = 12
      PHASES = %i[forced chrome focus spacing fonts weight].freeze
      FORCED_STATES = { "hover" => %w[hover], "focus-visible" => %w[focus focus-visible] }.freeze
      TYPES = { "Document" => "document", "Stylesheet" => "stylesheet", "Script" => "script", "Font" => "font",
                "Image" => "image" }.freeze

      # What one snapshot measures: the widths, the motion window, the route and budget for
      # the page-weight row, and the phases to run.
      Plan = Struct.new(:widths, :motion_ms, :route, :phases, :budget, keyword_init: true) do
        def self.full(**given) = new(widths: [390, 360, 320, 1280], motion_ms: 6000, phases: PHASES, **given)

        def run?(phase) = phases.include?(phase)
        def window = Integer(motion_ms)
        def route_of(url) = route || URI(url).path
      end

      def self.snapshot(cdp, url, plan = Plan.full) = Run.new(cdp:, url:, plan:).snapshot

      def self.budget(route)
        rows = File.file?(BUDGETS) ? YAML.safe_load_file(BUDGETS).fetch("routes", {}) : {}
        (rows || {})[route]
      end

      # Transfer bytes by type from the session's Network events, against the route's row.
      def self.weight(events, route:, row: nil)
        types = {}
        bytes = Hash.new(0)
        events.each do |event|
          params = event["params"] || {}
          request = params["requestId"]
          method = event["method"]

          types[request] = TYPES[params["type"]] if method == "Network.responseReceived"
          type = types[request]
          bytes[type] += params["encodedDataLength"].to_i if type && method == "Network.loadingFinished"
        end
        { "route" => route, "bytes" => bytes, "budget" => row || budget(route) }
      end

      # One page through one plan, on one open session.
      class Run
        def initialize(cdp:, url:, plan:)
          @cdp = cdp
          @url = url
          @plan = plan
        end

        def snapshot
          snap = { "probe" => "design_laws", "url" => @url, "viewports" => [] }
          @plan.widths.each_with_index do |width, index|
            @cdp.clear_events if index.zero?
            load(width)
            snap["viewports"] << view(width, first: index.zero?)
            snap.merge!(first_width) if index.zero?
          end
          snap
        end

        private

        def first_width
          found = {}
          found["weight"] = weight if @plan.run?(:weight)
          found["fonts"] = fonts if @plan.run?(:fonts)
          window = @plan.window
          found["motion"] = watch(window) if window.positive?
          found
        end

        def weight = Capture.weight(@cdp.events, route: @plan.route_of(@url), row: @plan.budget)

        def watch(window) = @cdp.evaluate("window.__designLaws.watch(#{window})", await_promise: true)

        def load(width)
          @cdp.viewport(width, HEIGHTS.fetch(width, 800), mobile: width < 768)
          @cdp.navigate(@url)
          PROBE.each { |script| @cdp.evaluate(script) }
        end

        def phase(call) = @cdp.evaluate("window.__designLaws.#{call}")

        def view(width, first:)
          row = { "width" => width, "height" => HEIGHTS.fetch(width, 800), "page" => phase("page()"),
                  "elements" => phase("elements()"), "numbers" => phase("numbers()") }
          row["forced"] = forced(row["elements"]) if first && @plan.run?(:forced)
          row["chrome"] = chrome if @plan.run?(:chrome)
          row["focus"] = focus_walk if [390, 1280].include?(width) && @plan.run?(:focus)
          row["spacing"] = phase("spacing()") if @plan.run?(:spacing)
          row
        end

        def scrolled(script, wait:)
          @cdp.evaluate(script)
          sleep wait
          phase("chrome()")
        end

        def chrome
          { "top" => phase("chrome()"),
            "down" => scrolled("window.scrollBy(0, Math.round(innerHeight * 1.5))", wait: 0.45),
            "up" => scrolled("window.scrollBy(0, -80)", wait: 0.35),
            "deep" => scrolled("window.scrollTo(0, Math.round(innerHeight * 2))", wait: 0.45) }
        ensure
          @cdp.evaluate("window.scrollTo(0, 0)")
        end

        def focus_walk
          @cdp.evaluate("document.activeElement && document.activeElement.blur(); window.scrollTo(0, 0)")
          stops = TABS.times.filter_map do
            @cdp.press("Tab")
            phase("focused()")
          end
          stops.uniq { |stop| stop["key"] + stop["rect"].values.join(",") }
        end

        def forceable?(element)
          (element["tag"] == "a" && element["in_text"]) || AccessLaws.control?(element) || element["interactive"]
        end

        # Links in running text and every control, read again under forced :hover and :focus-visible.
        def forced(elements)
          elements.select { |element| forceable?(element) }.first(FORCED).to_h do |element|
            index = Integer(element["index"])
            selector = %([data-design-law="#{index}"])
            states = FORCED_STATES.transform_values do |pseudo|
              @cdp.force_pseudo_state(selector, pseudo)
              phase("styleOf(#{index})")
            end
            @cdp.force_pseudo_state(selector, [])
            [index.to_s, states]
          end
        end

        # The painted face for each distinct family, weight, style and caps request.
        def fonts
          %w[DOM.enable CSS.enable].each { |command| @cdp.command(command) }
          root = @cdp.command("DOM.getDocument", depth: 0).dig("root", "nodeId")
          requests = Array(phase("fontRequests()")).uniq { |row| row.values_at("family", "weight", "style", "caps") }
          requests.first(16).filter_map { |row| painted(row, root:) }
        end

        def painted(row, root:)
          selector = %([data-design-law="#{Integer(row["index"])}"])
          node = @cdp.command("DOM.querySelector", nodeId: root, selector:)["nodeId"].to_i
          row.merge("platform" => @cdp.command("CSS.getPlatformFontsForNode", nodeId: node)["fonts"]) unless node.zero?
        end
      end
    end
  end
end
