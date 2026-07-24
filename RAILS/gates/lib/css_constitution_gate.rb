# frozen_string_literal: true

require "yaml"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "gate_autofix"

module Deploy
  # Every SCSS/CSS under RAILS apps + shared must pass MASTER design constitution.
  # Documented product pens are allow-listed for intentional ornament (yep search shadow, etc.).
  # GATE_AUTOFIX=1 → mechanical fix + remeasure until clean or stuck.
  class CssConstitutionGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    MASTER_DESIGN = File.join(ROOT, "MASTER", "data", "design_rules.yml")
    APPS = %w[brgen amber bsdports shared].freeze

    PEN_ALLOW = %r{(?:^|/)(?:_search_yep|_jsfiddle_chrome|_marketplace_nav_bar|_marketplace_animated_logo)\.scss\z}

    FLAT_PATTERN = /box-shadow\s*:\s*(?!none\b)|text-shadow\s*:|backdrop-filter\s*:|filter\s*:[^;]*\bblur\(/i
    TWITTER_BLUE = /#1d9bf0|#1DA1F2/i
    LONG_TRANSITION = /transition(?:-duration)?\s*:\s*([4-9]\d\d|\d{4,})\s*ms/i
    PHYSICAL_LR = /^\s*(margin|padding|inset)-(left|right)\s*:|^\s*left\s*:|^\s*right\s*:/
    IMPORTANT = /!important\b/

    def self.run
      return run_once unless GateAutofix.enabled?

      GateAutofix.run_with_remeasure(self)
    end

    def self.run_once
      new.run_once
    end

    def run_once
      @result = GateResult.new
      @design = File.file?(MASTER_DESIGN) ? YAML.safe_load_file(MASTER_DESIGN) : {}
      touch = @design.dig("layout_rules", "touch", "target_min_px").to_i
      @result.fail("css_constitution: design_rules touch.target_min_px missing/invalid") if touch.positive? && touch < 44

      files = css_files
      @result.fail("css_constitution: no stylesheets found") if files.empty?
      @result.warn("css_constitution: scanning #{files.size} stylesheets")

      files.each { |path| scan(path) }
      @result
    end

    private

    def css_files
      # Source of truth only — never fingerprinted public/assets copies.
      APPS.flat_map do |app|
        bases = [
          File.join(RAILS, app, "app/assets/stylesheets"),
          (File.join(RAILS, app, "app/assets/stylesheets") if app == "shared"),
        ].compact
        bases = [File.join(RAILS, "shared", "app/assets/stylesheets")] if app == "shared"
        bases.flat_map do |base|
          next [] unless File.directory?(base)

          Dir.glob(File.join(base, "**/*.{scss,css}")).reject do |p|
            p.include?("/vendor/") || p.include?("/node_modules/") || p.include?("/builds/") ||
              p.match?(/\.map\z/)
          end
        end
      end.uniq
    end

    def scan(path)
      rel = path.sub(RAILS + "/", "")
      body = File.read(path)
      pen = path.match?(PEN_ALLOW)

      unless pen
        if body.match?(FLAT_PATTERN)
          @result.fail("css_constitution flat_ui: #{rel}")
        end
      end

      if body.match?(TWITTER_BLUE)
        @result.fail("css_constitution no_twitter_blue: #{rel}")
      end

      body.scan(LONG_TRANSITION).flatten.each do |ms|
        next if body.match?(/prefers-reduced-motion:\s*reduce/i)

        @result.fail("css_constitution motion: #{rel} transition #{ms}ms > 300ms") if ms.to_i > 300
      end

      if body.match?(PHYSICAL_LR) && !pen
        hits = body.lines.count { |l| l.match?(PHYSICAL_LR) && !l.match?(%r{^\s*//}) }
        @result.fail("css_constitution logical_props: #{rel} (#{hits} physical left/right)") if hits > 12
      end

      lines = body.lines.size
      if lines > 200 && !File.basename(path).start_with?("application")
        @result.warn("css_constitution size: #{rel} is #{lines} lines (budget 200)") if lines > 250
        # Hard fail only for app-local vertical sheets, not shared shells
        if lines > 400 && rel.match?(%r{\A(brgen|amber|bsdports)/app/assets/stylesheets/_vertical_})
          @result.fail("css_constitution size: #{rel} is #{lines} lines (hard fail >400)")
        end
      end

      if body.match?(/@keyframes|animation\s*:/i) && !body.match?(/prefers-reduced-motion:\s*reduce/i)
        @result.fail("css_constitution reduced_motion: #{rel} animates without prefers-reduced-motion")
      end
    end
  end
end
