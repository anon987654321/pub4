# frozen_string_literal: true

require "yaml"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/gate_autofix"
require_relative "../../../tools/design/master_design"
require_relative "../../../tools/design/scss_rules"
require_relative "../../../tools/design/frontend_rule_set"
require_relative "../../support/css_spacing_scans"
require_relative "../../support/css_weight"
require_relative "../../support/css_caps_tracking"

module Deploy
  # Every SCSS/CSS under RAILS apps + shared must pass MASTER design constitution.
  # Documented product pens are allow-listed for intentional ornament (yep search shadow, etc.).
  # GATE_AUTOFIX=1 → mechanical fix + remeasure until clean or stuck.
  class CssConstitutionGate
    include CssSpacingScans
    include CssWeight
    include CssCapsTracking

    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    MASTER_DESIGN = File.join(ROOT, "MASTER", "data", "rules.yml")
    APPS = %w[brgen amber bsdports shared].freeze

    # `: none` is how a stylesheet *complies* with flat_ui, so it cannot be the
    # thing that fails it. text-shadow and backdrop-filter had no exclusion at
    # all, and box-shadow's did not work: `\s*(?!none\b)` lets the `\s*`
    # backtrack to zero width, so the lookahead runs against " none" — which is
    # not "none" — and succeeds. `box-shadow: none` matched; only the unspaced
    # `box-shadow:none` was ever excluded.
    #
    # The assertion has to cover the whitespace it is skipping, so it goes
    # before it rather than after. Nothing in RAILS writes the compliant form
    # today, which is why this never showed: the first stylesheet to turn an
    # effect off explicitly would have been the one penalised for it, and that
    # stylesheet was MASTER's face.
    FLAT_PATTERN = /box-shadow\s*:(?!\s*none\b)|text-shadow\s*:(?!\s*none\b)|backdrop-filter\s*:(?!\s*none\b)|filter\s*:[^;]*\bblur\(/i
    TWITTER_BLUE = /#1d9bf0|#1DA1F2/i
    LONG_TRANSITION = /transition(?:-duration)?\s*:\s*([4-9]\d\d|\d{4,})\s*ms/i
    PHYSICAL_LR = /^\s*(margin|padding|inset)-(left|right)\s*:|^\s*left\s*:|^\s*right\s*:/
    IMPORTANT = /!important\b/
    REDUCED_MOTION = /@media[^{]*prefers-reduced-motion/
    SPACING = /\b(?:margin|padding|gap|row-gap|column-gap|inset)(?:-(?:top|right|bottom|left|inline|block)(?:-(?:start|end))?)?\s*:\s*([^;{]+)/
# A number inside a var() fallback is the token's own declared value, not a
# spacing literal anyone chose. `calc(var(--chrome-inset, 12px) +
# var(--tap-min, 44px) + var(--space-1, 4px))` names three tokens and no
# numbers, and scanning the raw declaration counted all three — so writing
# the compliant form scored a rhythm finding. --tap-min made it worse: 44 is
# tap_min, it is on layout_rules.grid.allowed_spacing_px and on
# design_tokens scale.space_px, and it is absent from the
# pixel_perfection.eight_px_rhythm list this gate actually reads, so the
# one number guaranteed to appear in a tap-target fallback was the one
# number the allowlist rejected.
VAR_FALLBACK = /var\(\s*--[\w-]+\s*,[^()]*\)/
    HEX = /#[0-9a-fA-F]{3,8}\b/
    COMMENT = %r{\A\s*(?://|/\*|\*)}

    # design_rules.yml's whole `typography` block was the last section it
    # declares that nothing read. flat_ui, eight_px_rhythm, magic hex and
    # contrast all got a reader; type_scale, hierarchy.max_font_weights,
    # letter_spacing.all_caps_min_em and line_height did not. Measured across
    # the 82 source stylesheets on 2026-08-09: 71 distinct font-size values
    # against max_font_sizes 8, seven font weights against max_font_weights 3,
    # and two rival size ladders in the same tree — the token one
    # (12/14/16/18/20) and a hardcoded 13/15/17 borrowed from x.com.
    FONT_SIZE = /(?:\A|[;{\s])font-size\s*:\s*([^;}]+)/
    FONT_WEIGHT = /(?:\A|[;{\s])font-weight\s*:\s*([^;}]+)/
    # line_height was the one typography key with no reader. The --leading-*
    # ladder in _typography.scss is the vocabulary, so a literal — even one equal
    # to a step — is leading that retuning the token cannot reach.
    LINE_HEIGHT = /(?:\A|[;{\s])line-height\s*:\s*([^;}]+)/
    TIMING = /(?:transition(?:-timing-function)?|animation)\s*:\s*([^;}]+)/
    # Keyword timing functions are what CINEMA_PALETTE ("cubic-bezier easing on
    # every transition") exists to forbid; the tokens are the way to satisfy it.
    KEYWORD_EASING = /(?<![-\w])(?:ease|ease-in|ease-out|ease-in-out|linear)(?![-\w(])/
    # Relative and print units are correct as written: `em` sizes an inline
    # optical correction against its own parent, `pt` is the right unit inside
    # @media print. Neither belongs to the scale this counts.
    RELATIVE_SIZE = /\A[\d.]+(?:em|%|pt|ex|ch)\z/

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
    BUDGET_PATH = File.expand_path("../../data/css_budget.yml", __dir__)

    def self.run
      return run_once unless GateAutofix.enabled?

      GateAutofix.run_with_remeasure(self)
    end

    def self.run_once
      new.run_once
    end

    def run_once
      @result = GateResult.new
      @design = Operator::MasterDesign.blocks(MASTER_DESIGN)
      check_tap_token

      files = css_files
      files.empty? ? @result.fail("css_constitution: no stylesheets found") : @result.checked!(files.size)
      @result.warn("css_constitution: scanning #{files.size} stylesheets")

      # Seeded, not defaulted: a rule that falls to zero has to still appear here
      # or it never reaches judge_budgets and its ceiling never ratchets down.
      @tally = {
        "important" => [], "rhythm" => [], "magic_hex" => [],
        "type_scale" => [], "weight_ladder" => [],
        "child_margin" => [], "card_padding" => [], "leading" => [],
      }
      files.each { |path| scan(path) }
      judge_budgets
      check_weight
      @result
    end

    def budgets
      @budgets ||= begin
        raise "budget missing: #{BUDGET_PATH}" unless File.file?(BUDGET_PATH)
        data = YAML.safe_load_file(BUDGET_PATH)
        rules = data&.dig("rules")
        raise "budget has no rules: #{BUDGET_PATH}" unless rules.is_a?(Hash)
        rules
      end
    rescue StandardError => e
      @result.inconclusive!("css_constitution: budget unreadable (#{e.class}: #{e.message}) — CSS ceilings were not measured")
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

    # Both ladders are read out of the stylesheets that declare them rather than
    # restated here, the way rhythm_lint reads MASTER's rhythm directly. A gate
    # carrying its own copy of the scale is a second source that drifts, and
    # the drift is invisible precisely because both files look maintained.
    def token_path(name)
      File.join(RAILS, "shared", "app/assets/stylesheets", name)
    end

    def size_ladder
      @size_ladder ||= begin
        body = File.file?(token_path("_tokens.scss")) ? File.read(token_path("_tokens.scss")) : ""
        body.scan(/--text-[\w-]+\s*:\s*([\d.]+rem)\s*;/).flatten.map { |v| normalize_size(v) }.uniq
      end
    end

    def weight_ladder
      @weight_ladder ||= begin
        body = File.file?(token_path("_dialect_tokens.scss")) ? File.read(token_path("_dialect_tokens.scss")) : ""
        body.scan(/--weight-[\w-]+\s*:\s*(\d{3})\s*;/).flatten.map(&:to_i).uniq
      end
    end

    # 0.875rem, .875rem and 14px are the same step; compare in px so a call site
    # cannot dodge the ladder by changing units.
    def normalize_size(value)
      case value.strip
      when /\A([\d.]*\d)rem\z/ then (Regexp.last_match(1).to_f * 16).round(2)
      when /\A([\d.]*\d)px\z/ then Regexp.last_match(1).to_f.round(2)
      end
    end

    def count_typography(where, line)
      if (m = line.match(FONT_SIZE))
        value = m[1].strip
        unless value.start_with?("var(", "clamp(", "calc(", "inherit") || value.match?(RELATIVE_SIZE)
          px = normalize_size(value)
          @tally["type_scale"] << "#{where} #{value}" if px && !size_ladder.include?(px)
        end
      end

      if (m = line.match(LINE_HEIGHT))
        value = m[1].strip
        (@tally["leading"] ||= []) << "#{where} #{value}" unless value.start_with?("var(", "inherit", "normal")
      end

      return unless (m = line.match(FONT_WEIGHT))

      value = m[1].strip
      return if value.start_with?("var(", "$") || %w[inherit normal bold].include?(value)

      @tally["weight_ladder"] << "#{where} #{value}" unless weight_ladder.include?(value.to_i)
    end

    # Strip comments before counting, rather than skipping lines that *start*
    # with a comment marker.
    #
    # COMMENT only matches a leading //, /* or *. This tree writes multi-line
    # block comments with plain indented continuation lines and no leading star,
    # which is most of them — so every continuation line was counted as code.
    # Measured across the 81 source stylesheets: 32 comment lines carrying a px
    # value inflated the rhythm budget, 10 carrying a hex inflated magic_hex
    # (including _empty_state.scss:69, which is why a survey of "hex equal to a
    # token" reported --accent equal to a light grey), and one carrying the word
    # !important inflated that budget by one — a comment whose subject was
    # choosing specificity *instead of* !important.
    #
    # A budget that counts its own prose ratchets against documentation.
    def strip_comments(body)
      out = +""
      rest = body.dup
      until rest.empty?
        if (open = rest.index("/*"))
          out << rest[0...open].sub(%r{//.*}, "")
          close = rest.index("*/", open + 2)
          # Keep the newlines so line numbers survive.
          span = close ? rest[open..close + 1] : rest[open..]
          out << ("\n" * span.count("\n"))
          rest = close ? rest[(close + 2)..] : ""
        else
          out << rest.gsub(%r{//.*}, "")
          rest = ""
        end
      end
      out
    end

    def count_budget_rules(path, rel, body)
      token_source = TOKEN_SOURCES.include?(File.basename(path))
      allowed = rhythm_allowlist
      in_face = false
      depth = 0
      motion_depth = nil
      strip_comments(body).each_line.with_index do |line, index|
        next if line.match?(COMMENT)

        # @font-face descriptors name the weight and size of a *file*. They are
        # not UI type and must not be measured against the ladder, or restoring
        # a Bold face to 700 reads as drift off a 400/600/800 scale.
        in_face = true if line.match?(/@font-face/)
        face_line = in_face
        in_face = false if in_face && line.match?(/\A\s*\}\s*\z/)

        # A reduced-motion override has to beat whatever specificity set the
        # animation, so !important is the pattern there rather than a lapse.
        # 70 of this tree's 137 sit inside one.
        motion_depth ||= depth if line.match?(REDUCED_MOTION)
        depth += line.count("{") - line.count("}")
        where = "#{rel}:#{index + 1}"
        @tally["important"] << where if line.match?(IMPORTANT) && motion_depth.nil?
        @tally["magic_hex"] << where if !token_source && line.match?(HEX)
        count_typography(where, line) unless token_source || face_line
        motion_depth = nil if motion_depth && depth <= motion_depth
        next if allowed.empty?

        spacing = line.gsub(VAR_FALLBACK, "var()").match(SPACING)
        next unless spacing

        spacing[1].scan(/(-?\d+(?:\.\d+)?)px/).flatten.each do |value|
          # Compare magnitude: a -64px pull is as on-rhythm as a 64px push, and
          # the allowlist only carries the positive half. Six negative offsets
          # were counted as violations for their sign alone.
          number = value.to_f.abs
          @tally["rhythm"] << "#{where} #{value}px" unless number == number.to_i && allowed.include?(number.to_i)
        end
      end
    end

    def css_files
      # Source of truth only — never fingerprinted public/assets copies.
      #
      # Engine stylesheet directories are globbed as well as the app's own. brgen's
      # verticals are mountable engines, and their styles live in brgen's
      # application.scss today; an engine that grows a stylesheet of its own again
      # must not land outside every budget here, which is what happened when the
      # verticals first moved and 1406 lines of CSS went unmeasured.
      rails = APPS.flat_map do |app|
        bases = [File.join(RAILS, app, "app/assets/stylesheets")]
        bases.concat(Dir.glob(File.join(RAILS, app, "engines/*/app/assets/stylesheets")))
        bases.flat_map do |base|
          next [] unless File.directory?(base)

          Dir.glob(File.join(base, "**/*.{scss,css}")).reject do |p|
            p.include?("/vendor/") || p.include?("/node_modules/") || p.include?("/builds/") ||
              p.match?(/\.map\z/)
          end
        end
      end

      (rails + master_web_files).uniq
    end

    # The fourth public surface. ai.brgen.no is reachable from brgen's own top
    # nav, so a visitor crosses from a gated app into an ungated one without
    # leaving the product — and this gate had never opened it, because MASTER
    # keeps its stylesheets in web/public rather than app/assets/stylesheets and
    # every glob here is shaped for a Rails app.
    #
    # Named files, not a glob: web/public also holds fingerprinted precompile
    # output (24 face-*.css copies at the last count), and scanning build
    # artifacts is what the "source of truth only" note above forbids.
    MASTER_WEB = %w[MASTER/web/public/face.css MASTER/web/public/chat_upload.css].freeze

    def master_web_files
      MASTER_WEB.map { |rel| File.join(ROOT, rel) }.select { |p| File.file?(p) }
    end

    # Product pens reproduce an outside design exactly, so the flat, spacing and
    # logical-property checks read the stylesheet with them blanked: a pen's own
    # partial reads as empty, and a pen inside an app stylesheet leaves the rest
    # of that file measured.
    def without_pens(path, body)
      return "" if path.match?(Shared::FrontendRuleSet::PRODUCT_PEN_FILES)

      Operator::ScssRules.without(body, Shared::FrontendRuleSet::PRODUCT_PEN_SELECTORS)
    end

    def scan(path)
      rel = path.sub(RAILS + "/", "")
      body = File.read(path)
      hygiene = without_pens(path, body)
      count_budget_rules(path, rel, body)
      scan_spacing(rel, hygiene)

      if hygiene.match?(FLAT_PATTERN)
        @result.fail("css_constitution flat_ui: #{rel}")
      end

      if body.match?(TWITTER_BLUE)
        @result.fail("css_constitution no_twitter_blue: #{rel}")
      end

      body.scan(LONG_TRANSITION).flatten.each do |ms|
        next if body.match?(/prefers-reduced-motion:\s*reduce/i)

        @result.fail("css_constitution motion: #{rel} transition #{ms}ms > 300ms") if ms.to_i > 300
      end

      hits = hygiene.lines.count { |l| l.match?(PHYSICAL_LR) && !l.match?(%r{^\s*//}) }
      @result.fail("css_constitution logical_props: #{rel} (#{hits} physical left/right)") if hits > 12

      # Code lines, like every other budget in this file and like the rest of the
      # tree's size rules, so explaining the CSS never counts against it. Each
      # app's application.scss is exempt: the operator asked for one stylesheet
      # per app, and file_length_ratchet_test.rb holds each one to a ceiling.
      lines = strip_comments(body).each_line.count do |line|
        stripped = line.strip
        !stripped.empty? && !stripped.start_with?("//", "/*", "*")
      end
      if lines > 250 && !File.basename(path).start_with?("application")
        @result.warn("css_constitution size: #{rel} is #{lines} code lines (budget 200)")
      end

      if body.match?(/@keyframes|animation\s*:/i) && !body.match?(/prefers-reduced-motion:\s*reduce/i)
        @result.fail("css_constitution reduced_motion: #{rel} animates without prefers-reduced-motion")
      end

      check_easing(rel, body)
      check_caps_tracking(rel, body)
      check_font_face_descriptors(rel, body)
    end

    # Inside @font-face, font-weight/style/stretch are *descriptors* naming what
    # is in the file, not properties styling an element, and var() is invalid
    # there — the browser drops the whole declaration and the face stops
    # matching. A bulk weight-tokenisation pass rewrote four of them on
    # 2026-08-09, including the JetBrainsMono Bold face, which would have told
    # the browser its bold file was the body weight.
    def check_font_face_descriptors(rel, body)
      in_face = false
      strip_comments(body).each_line.with_index do |line, index|
        in_face = true if line.match?(/@font-face/)
        if in_face && line.match?(/font-(?:weight|style|stretch)\s*:\s*var\(/)
          @result.fail("css_constitution font_face: #{rel}:#{index + 1} uses var() in an @font-face " \
                       "descriptor — it must state the weight of the file in src, not a UI token")
        end
        in_face = false if in_face && line.match?(/\A\s*\}\s*\z/)
      end
    end

    # Easing reached zero in the 2026-08-09 typography pass, as caps tracking did,
    # so it is a hard check rather than a ceiling — the ceilings in css_budget.yml
    # exist for debt that predates a reader, not for rules already clean.
    def check_easing(rel, body)
      strip_comments(body).each_line.with_index do |line, index|
        next unless (m = line.match(TIMING))

        value = m[1]
        # `none` is how a reduced-motion block turns motion off, not an easing.
        next if value.match?(/\bnone\b/) || value.include?("steps(")
        next unless value.match?(KEYWORD_EASING)

        @result.fail("css_constitution easing: #{rel}:#{index + 1} uses a keyword timing function " \
                     "(#{value.strip}) — CINEMA_PALETTE wants a cubic-bezier; use var(--ease-out) et al")
      end
    end
  end
end
