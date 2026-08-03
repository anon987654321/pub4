# frozen_string_literal: true

require "yaml"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../support/gate_autofix"

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
    SPACING = /\b(?:margin|padding|gap|row-gap|column-gap|inset)(?:-(?:top|right|bottom|left|inline|block)(?:-(?:start|end))?)?\s*:\s*([^;{]+)/
    HEX = /#[0-9a-fA-F]{3,8}\b/
    COMMENT = %r{\A\s*(?://|/\*|\*)}

    # The palette lives here; a hex literal in either file is the definition the
    # rest of the tree is supposed to reference.
    TOKEN_SOURCES = %w[_tokens.scss _dialect_tokens.scss].freeze

    # Three rules design_rules.yml and style.yml declare and nothing read.
    # IMPORTANT sat in this file with zero call sites while 119 !important
    # shipped; eight_px_rhythm was checked only where the tokens are defined,
    # never where px is written; magic_color_hex_ban_inline had no reader at all.
    #
    # Ceilings rather than zeros, in the shape of constitutional_budget.yml: these
    # are three shipping apps' accumulated craft debt, and a gate that goes red on
    # arrival is a gate people route around. What a ceiling buys is that the next
    # one fails.
    BUDGET_PATH = File.expand_path("../data/css_budget.yml", __dir__)

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

      # Seeded, not defaulted: a rule that falls to zero has to still appear here
      # or it never reaches judge_budgets and its ceiling never ratchets down.
      @tally = { "important" => [], "rhythm" => [], "magic_hex" => [] }
      files.each { |path| scan(path) }
      judge_budgets
      @result
    end

    def budgets
      @budgets ||= (YAML.safe_load_file(BUDGET_PATH)&.dig("rules") || {})
    rescue StandardError
      {}
    end

    attr_reader :tally

    private

    def judge_budgets
      @tally.each do |rule, hits|
        ceiling = budgets[rule]
        if ceiling.nil?
          @result.warn("css_constitution #{rule}: #{hits.size} with no ceiling in css_budget.yml")
          next
        end

        if hits.size > ceiling
          hits.first(8).each { |hit| @result.warn("css_constitution #{rule}: #{hit}") }
          @result.fail("css_constitution #{rule}: #{hits.size} exceeds ceiling #{ceiling} (+#{hits.size - ceiling}) — " \
                       "fix them, or record a new ceiling with a reason")
        elsif hits.size < ceiling
          @result.warn("css_constitution #{rule}: #{hits.size}, under its #{ceiling} ceiling " \
                       "(-#{ceiling - hits.size}) — GATE_CSS_RATCHET=1 records the new low")
          ratchet(rule, hits.size)
        else
          @result.warn("css_constitution #{rule}: at its #{ceiling} ceiling")
        end
      end
    end

    def ratchet(rule, count)
      return unless GateResult.flag?("GATE_CSS_RATCHET")

      body = File.read(BUDGET_PATH)
      File.write(BUDGET_PATH, body.sub(/^  #{Regexp.escape(rule)}: \d+$/, "  #{rule}: #{count}"))
    end

    def rhythm_allowlist
      @rhythm_allowlist ||= Array(@design.dig("pixel_perfection", "eight_px_rhythm")).map(&:to_i)
    end

    def count_budget_rules(path, rel, body)
      token_source = TOKEN_SOURCES.include?(File.basename(path))
      allowed = rhythm_allowlist
      body.each_line.with_index do |line, index|
        next if line.match?(COMMENT)

        where = "#{rel}:#{index + 1}"
        @tally["important"] << where if line.match?(IMPORTANT)
        @tally["magic_hex"] << where if !token_source && line.match?(HEX)
        next if allowed.empty?

        spacing = line.match(SPACING)
        next unless spacing

        spacing[1].scan(/(-?\d+(?:\.\d+)?)px/).flatten.each do |value|
          number = value.to_f
          @tally["rhythm"] << "#{where} #{value}px" unless number == number.to_i && allowed.include?(number.to_i)
        end
      end
    end

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
      count_budget_rules(path, rel, body)

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
