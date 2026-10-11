# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "visual_cross_page_drift"

module Master
  module Fix
    # The cross-page overlay compares pages of ONE app; this compares the same
    # shared primitive (header, nav link, footer, button, form control) ACROSS
    # apps, from the computed styles the geometry walk already captured. Where
    # brgen, its verticals and bsdports render the same primitive with different
    # spacing, radius, type size, weight, border or colour, it emits a "unify
    # this primitive" finding pointing at the shared stylesheet, the one place a
    # fix applies to all of them. Report only: nothing here edits a stylesheet.
    #
    # Amber has its own editorial identity (it belongs to Ragnhild). Its values
    # are listed as informational deviations and never proposed for change.
    class CrossAppConsistency
      LAW = "CROSS_APP_CONSISTENCY"
      EDITORIAL_APPS = %w[amber].freeze
      IGNORED_APPS = %w[master].freeze
      SHARED_SHEETS = {
        "header" => "_layout_chrome.scss", "nav_link" => "_layout_chrome.scss", "footer" => "_layout_chrome.scss",
        "button" => "_buttons.scss", "form_control" => "_components.scss"
      }.freeze
      SHARED_DIR = "RAILS/__shared/app/assets/stylesheets"
      NUMERIC = %w[font_size line_height height letter_spacing].freeze
      TOLERANCE = 0.5
      PER_SURFACE = 3
      # Properties compared; each present in the geometry payload.
      PROPS = %w[height font_size font_weight line_height letter_spacing border_radius border_width border_color
                    padding box_shadow color bg].freeze
      TOKEN_PROPS = %w[color bg border_color].freeze

      Sample = Data.define(:app, :viewport, :primitive, :selector, :style)

      # Verticals are surfaces of the brgen app under their own host; each is
      # compared as its own member so a vertical that drifts from core shows.
      def self.member(surface)
        app = surface.app.to_s
        return app unless app == "brgen" && surface.host && surface.label.to_s != "core"

        "brgen:#{surface.label}"
      end

      def self.from_captures(captures)
        Array(captures).select { |c| resting?(c) }.flat_map do |capture|
          surface = capture[:surface]
          elements = Array(capture.dig(:payload, "elements"))
          primitives(elements).flat_map do |primitive, found|
            found.first(PER_SURFACE).map do |el|
              Sample.new(app: member(surface), viewport: surface.viewport.to_s, primitive:, selector: el["key"].to_s,
                         style: PROPS.to_h { |p| [p, el[p] || (p == "height" ? el.dig("frect", "h") : nil)] }.compact)
            end
          end
        end
      end

      # The visual pass's hook: a no-op unless MASTER_CROSS_APP=1. Writes the
      # report beside the dead-CSS one; the pass itself is unchanged.
      def self.write_for(captures)
        return unless ENV["MASTER_CROSS_APP"] == "1"

        new(from_captures(captures), out_dir: File.expand_path("../../.master/cross_app", __dir__)).write
      end

      def self.resting?(capture)
        capture.dig(:payload, "composition", "state").to_s.then { |s| s.empty? || s == "resting" }
      end

      def self.primitives(elements)
        nav = ->(e) { e["key"].to_s.split(">").any? { |seg| seg.start_with?("nav") } }
        controls = elements.select { |e| e["tag"] == "input" || %w[select textarea].include?(e["tag"]) }
        {
          "header" => elements.select { |e| e["tag"] == "header" },
          "nav_link" => elements.select { |e| %w[a button].include?(e["tag"]) && nav.(e) },
          "footer" => elements.select { |e| e["tag"] == "footer" },
          "button" => elements.select { |e| VisualCrossPageDrift.action?(e) && !nav.(e) },
          "form_control" => controls.reject { |e| %w[submit hidden checkbox radio button].include?(e["input_type"]) },
        }
      end

      def initialize(samples, root: File.expand_path("../../..", __dir__), out_dir: nil)
        @samples = samples.reject { |s| IGNORED_APPS.include?(s.app.split(":").first) }
        @root = root
        @out_dir = out_dir
      end

      # { inconsistencies:, amber_deviations:, findings:, text: }
      def report
        inconsistencies = []
        deviations = []
        @samples.group_by { |s| [s.viewport, s.primitive] }.sort.each do |(viewport, primitive), group|
          members = group.group_by(&:app)
          PROPS.each do |prop|
            modes = members.transform_values { |ss| mode(ss, prop) }.compact.reject { |_, v| v[:value].nil? }
            shared = modes.reject { |app, _| editorial?(app) }
            if distinct?(shared.values.map { |v| v[:value] }, prop)
              inconsistencies << row(viewport, primitive, prop, shared)
            end
            deviations.concat(amber_rows(viewport, primitive, prop, modes, shared)) if shared.any?
          end
        end
        findings = inconsistencies.map { |r| finding(r) }
        { inconsistencies:, amber_deviations: deviations, findings:, text: text(inconsistencies, deviations) }
      end

      def write(report = self.report)
        return unless @out_dir

        FileUtils.mkdir_p(@out_dir)
        File.write(File.join(@out_dir, "cross_app.json"), JSON.pretty_generate(report.except(:text)))
        File.write(File.join(@out_dir, "cross_app.txt"), report[:text])
      end

      private

      def editorial?(app) = EDITORIAL_APPS.include?(app.split(":").first)

      def mode(samples, prop)
        values = samples.filter_map { |s| s.style[prop] }
        return if values.empty?

        value = values.tally.max_by { |_, n| n }.first
        { value:, selector: samples.find { |s| s.style[prop] == value }.selector }
      end

      def distinct?(values, prop)
        return false if values.size < 2
        return values.minmax.then { |lo, hi| hi.to_f - lo.to_f > TOLERANCE } if NUMERIC.include?(prop)

        values.map(&:to_s).uniq.size > 1
      end

      def row(viewport, primitive, prop, shared)
        { viewport:, primitive:, prop:, token: TOKEN_PROPS.include?(prop),
          values: shared.transform_values { |v| v[:value] }, selectors: shared.transform_values { |v| v[:selector] } }
      end

      # Amber against the shared consensus: listed, never proposed.
      def amber_rows(viewport, primitive, prop, modes, shared)
        consensus = shared.values.map { |v| v[:value] }.first
        modes.select { |app, _| editorial?(app) }.filter_map do |app, v|
          next unless distinct?([consensus, v[:value]], prop)

          { app:, viewport:, primitive:, prop:, value: v[:value], shared_value: consensus, selector: v[:selector], informational: true }
        end
      end

      def finding(r)
        sheet = "#{SHARED_DIR}/#{SHARED_SHEETS.fetch(r[:primitive])}"
        who = r[:values].map { |app, v| "#{app}=#{v}" }.join(" ")
        { law: LAW, severity: :info, advisory: true, primitive: r[:primitive], prop: r[:prop], viewport: r[:viewport],
          values: r[:values], selectors: r[:selectors], fix_in: sheet,
          message: "unify this primitive: #{r[:primitive]} #{r[:prop]} differs at #{r[:viewport]} (#{who}); set it once in #{sheet}" }
      end

      def text(inconsistencies, deviations)
        lines = ["cross-app consistency (report only)", "shared apps: #{inconsistencies.size} inconsistent values"]
        inconsistencies.each do |r|
          lines << "  #{r[:primitive]} #{r[:prop]} @#{r[:viewport]}: #{r[:values].map { |a, v| "#{a}=#{v}" }.join(" ")}  -> #{SHARED_SHEETS.fetch(r[:primitive])}"
        end
        lines << "amber editorial deviations (informational, not for change): #{deviations.size}"
        deviations.each { |d| lines << "  #{d[:primitive]} #{d[:prop]} @#{d[:viewport]}: amber=#{d[:value]} shared=#{d[:shared_value]}" }
        lines.join("\n") + "\n"
      end
    end
  end
end
