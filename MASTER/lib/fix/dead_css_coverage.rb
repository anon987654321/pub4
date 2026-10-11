# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "scss_rules"

module Master
  module Fix
    # The rendered half of the dead-CSS proof. Chrome's rule-usage tracking says
    # which style rules matched an element while a surface was on screen; this
    # folds that into one store per app, so a rule is "used" if ANY captured
    # surface, viewport or composition state ever matched it. Usage is keyed by
    # normalized selector text because stylesheet ids are per-navigation.
    #
    #   store = DeadCssCoverage.new(dir:)
    #   store.start(cdp)                 # page loaded; tracking forces a restyle
    #   ...walk states...
    #   store.finish(cdp, app: "brgen", surface: "brgen/home/desktop")
    class DeadCssCoverage
      DIR = File.expand_path("../../.master/dead_css", __dir__)

      attr_reader :dir, :errors

      def initialize(dir: DIR)
        @dir = dir
        @errors = []
      end

      # Tracks usage around a block (the composition states of one surface) and
      # returns the block's value. Tracking that cannot start never stops the walk.
      def track(cdp, surface)
        tracking = start(cdp)
        yield
      ensure
        finish(cdp, app: surface.app.to_s, surface: surface.id) if tracking
      end

      # The visual pass's hook: a no-op unless MASTER_DEAD_CSS=1, so a rendered
      # review costs nothing extra by default.
      def self.around(cdp, surface, &block)
        return yield unless ENV["MASTER_DEAD_CSS"] == "1"

        (@shared ||= new).track(cdp, surface, &block)
      end

      def start(cdp)
        cdp.command("DOM.enable")
        cdp.command("CSS.enable")
        cdp.command("CSS.startRuleUsageTracking")
        true
      rescue StandardError => e
        @errors << "start: #{e.class}: #{e.message}"
        false
      end

      def finish(cdp, app:, surface:)
        usage = cdp.command("CSS.stopRuleUsageTracking").fetch("ruleUsage", [])
        texts = usage.map { |u| u["styleSheetId"] }.uniq.to_h { |id| [id, cdp.command("CSS.getStyleSheetText", styleSheetId: id)["text"].to_s] }
        merge(app, self.class.fold(usage, texts), surface)
      rescue StandardError => e
        @errors << "finish #{surface}: #{e.class}: #{e.message}"
        nil
      end

      # { normalized selector => used } from one page's usage records.
      def self.fold(usage, texts)
        usage.each_with_object({}) do |u, seen|
          text = texts[u["styleSheetId"]].to_s
          prelude = text[u["startOffset"].to_i...u["endOffset"].to_i].to_s[/\A[^{]*/].to_s.strip
          next if prelude.empty? || prelude.start_with?("@")

          ScssRules.split_list(prelude).each do |selector|
            key = ScssRules.normalize(selector)
            seen[key] = !!(seen[key] || u["used"])
          end
        end
      end

      def self.load(app, dir: DIR)
        path = File.join(dir, "coverage", "#{app}.json")
        File.file?(path) ? JSON.parse(File.read(path)) : { "app" => app, "surfaces" => [], "selectors" => {} }
      end

      def merge(app, folded, surface)
        data = self.class.load(app, dir: @dir)
        folded.each { |sel, used| data["selectors"][sel] = data["selectors"][sel] || used }
        data["surfaces"] = (data["surfaces"] + [surface]).uniq
        path = File.join(@dir, "coverage", "#{app}.json")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(data))
        data
      end
    end
  end
end
