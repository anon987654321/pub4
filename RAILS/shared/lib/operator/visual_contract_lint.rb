# frozen_string_literal: true

require_relative "baseline_ratchet"
require_relative "master_design"

module Operator
  # The visual decisions that are law, made measurable. Four checks, one ratchet
  # each; every ceiling only descends.
  #
  #   low_contrast — WCAG ratios computed from the COMPILED bundles, because the
  #     build is what production wears (WIRING_NOTES: "read the second table
  #     before the first"). Text pairs read large_text_contrast (AA 4.5) from
  #     rules.yml; UI/accent pairs stay at WCAG non-text 3:1. AAA 7.0
  #     (normal_text_contrast) is design_metrics' budgeted gate — raising this
  #     lint's floor to 7.0 floods the compiled bundles. Custom properties are
  #     resolved one var() hop within the same bundle; pairs that don't resolve
  #     to hex are skipped, not guessed.
  #
  #   unreserved_image — an image with no width/height/aspect at the call site
  #     is a layout shift waiting on the network (TEMPORAL_COUPLING). Counted
  #     per call site; reserve with size attributes or an aspect-ratio class.
  #
  #   accent_on_prose — brgen's identity is grayscale ("the direction itself,
  #     not a rotated hue" — _root.scss); accent belongs to interactive and
  #     state elements only. A `color: var(--accent)` under a non-interactive
  #     selector spends the one hue on body text.
  #
  #   compose_costume — reading surfaces must not wear the writing control's
  #     costume (CQS). Pins the regression that shipped once: .city-today
  #     dressed as the compose pill. The strip is a card; the pill is compose's.
  module VisualContractLint
    RAILS_ROOT = File.expand_path("../../..", __dir__)

    BUNDLES = {
      "brgen" => "brgen/app/assets/builds/application.css",
      "amber" => "amber/app/assets/builds/application.css",
      "bsdports" => "bsdports/app/assets/builds/application.css",
    }.freeze

    TEXT_PAIRS = [ %w[--text --bg], %w[--text-secondary --surface], %w[--text-secondary --bg] ].freeze
    UI_PAIRS = [ %w[--accent --bg], %w[--danger --bg] ].freeze

    # `delete` and `fav` name controls this list could not see. `.comment-delete`
    # is a transparent bordereless button with `cursor: pointer`, and
    # `.deal-fav--on` is the on-state of a favourite button that carries
    # --tap-min in both axes. Both are the state-indicator case the 3:1 non-text
    # floor exists for, so both were reported as prose the moment the glob below
    # widened far enough to reach them.
    INTERACTIVE_SELECTOR = /\ba\b|button|\.btn|link|tab|chip|badge|action|:hover|:focus|active|vote|toggle|nav|pill|switch|control|icon|spinner|progress|ring|cursor|caret|brand|logo|accent|input|select|textarea|summary|delete|fav/i

    # All four measure 0: the light-theme vertical accents carry darkened
    # same-hue variants, the image helpers reserve intrinsically, and every raw
    # call site carries its pair or a reserved: container marker. Never raise
    # to silence.
    #
    # .price is not one of the four, and the reason written here was the wrong
    # one. It said INTERACTIVE_SELECTOR does not match .price — true, and beside
    # the point: accent_findings never opened the file. The glob was brgen's
    # stylesheet directory and .price's colour is at shared/_minimal.scss:474.
    #
    # Measured against the three built bundles rather than the sources, because
    # the build is what production wears. brgen's .price carries no colour at
    # all: _stack_brgen does not forward _minimal, and brgen redeclares .price in
    # _card_modifiers.scss with weight and size and nothing else, its own comment
    # saying the accent stays with interactive elements. amber's and bsdports'
    # .price do wear var(--accent), through _stack. So "does .price still wear
    # the accent" has two answers, and the one this file could have an opinion
    # about is already no.
    #
    # The other two are not brgen's to judge. amber is the luxury dialect and
    # bsdports is a green terminal; accent on text may be their identity, and
    # accent_on_prose is a claim about brgen's grayscale one. That is why
    # brgen_bundle_sources follows the bundle and not the tree.
    BASELINES = {
      "low_contrast" => 0,
      "unreserved_image" => 0,
      "accent_on_prose" => 0,
      "compose_costume" => 0,
      "btn_vocabulary" => 0,
    }.freeze

    Finding = Struct.new(:kind, :file, :detail)

    extend Operator::BaselineRatchet

    module_function

    def scan
      contrast_findings + image_findings + accent_findings + costume_findings + btn_findings
    end

    def run
      findings = scan
      over = counts(findings).select { |kind, count| count > BASELINES.fetch(kind) }
      counts(findings).each { |kind, count|
 puts "visual_contract_lint: #{kind} #{count} (baseline #{BASELINES.fetch(kind)})" }
      findings.each { |f| puts "  #{f.kind} #{f.file}: #{f.detail}" }
      over.each { |kind, count|
 warn "visual_contract_lint: #{kind} #{count} exceeds baseline #{BASELINES.fetch(kind)}" }
      over.empty?
    end

    # --- contrast -------------------------------------------------------------

    def contrast_findings
      BUNDLES.flat_map do |app, rel|
        path = File.join(RAILS_ROOT, rel)
        next [] unless File.file?(path)

        css = File.read(path, encoding: "UTF-8")
        tokens = root_tokens(css)
        pairs = TEXT_PAIRS.map { |p| p + [ text_contrast_min ] } + UI_PAIRS.map { |p| p + [ 3.0 ] }
        base = pairs.filter_map do |fg, bg, min|
          ratio = ratio_for(tokens, fg, bg)
          next unless ratio && ratio < min
          Finding.new("low_contrast", rel, "#{fg} on #{bg} = #{ratio.round(2)}:1 (needs #{min}:1)")
        end
        base + vertical_accent_findings(app, rel, css, tokens)
      end
    end

    # brgen's per-vertical accents repaint --accent under body.vertical-*; each
    # worn accent must clear 3:1 against the surface it sits on.
    def vertical_accent_findings(app, rel, css, tokens)
      return [] unless app == "brgen"

      surface = resolve(tokens, "--surface") || resolve(tokens, "--bg")
      return [] unless surface

      winners = {}
      css.scan(/(?:body\.vertical-|:root\[data-theme="light"\] body\.vertical-)(\w+)[^{]*\{[^}]*?--accent:\s*(#\h{3,6})/m) do |vertical, hex|
        winners[vertical] = hex # last declaration wins, matching the cascade in light mode
      end
      winners.filter_map do |vertical, hex|
        ratio = contrast_ratio(hex, surface)
        next unless ratio < 3.0
        Finding.new("low_contrast", rel,
"vertical-#{vertical} accent #{hex} on #{surface} = #{ratio.round(2)}:1 (needs 3:1)")
      end
end

    def root_tokens(css)
      tokens = {}
      css.scan(/:root[^{]*\{([^}]*)\}/m) do |(body)|
        body.scan(/(--[\w-]+):\s*([^;]+);/) { |name, value| tokens[name] = value.strip }
      end
      tokens
    end

    def resolve(tokens, name, depth = 0)
      return nil if depth > 3
      value = tokens[name]
      return nil unless value
      return value if value.match?(/\A#\h{3,6}\z/)
      inner = value[/var\((--[\w-]+)/, 1]
      inner ? resolve(tokens, inner, depth + 1) : nil
    end

    # The CI floor is AA. typography.accessibility.large_text_contrast is that
    # number in the law (4.5); normal_text_contrast (7.0) is design_metrics'.
    def accessibility_rules
      Operator::MasterDesign.dig("typography", "accessibility") || {}
    end

    def text_contrast_min
      value = accessibility_rules["large_text_contrast"].to_f
      value.positive? ? value : 4.5
    end

    def ratio_for(tokens, fg_name, bg_name)
      fg = resolve(tokens, fg_name)
      bg = resolve(tokens, bg_name)
      fg && bg ? contrast_ratio(fg, bg) : nil
    end

    def contrast_ratio(hex_a, hex_b)
      la, lb = [ relative_luminance(hex_a), relative_luminance(hex_b) ].sort.reverse
      (la + 0.05) / (lb + 0.05)
    end

    def relative_luminance(hex)
      hex = hex.delete("#")
      hex = hex.chars.map { |c| c * 2 }.join if hex.size == 3
      r, g, b = [ hex[0, 2], hex[2, 2], hex[4, 2] ].map do |channel|
        c = channel.to_i(16) / 255.0
        c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
      end
      0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    # --- image reservation ----------------------------------------------------

    # Raw <img> and bare image_tag only: responsive_image_tag and
    # lazy_image_tag reserve intrinsically (Shared::UiHelper#image_dimensions
    # rides every call), so the helper is the reservation.
    IMAGE_CALL = /(?:(?<!responsive_)(?<!lazy_)\bimage_tag[ (]|<img\b)[^\n]*/

    # `reserved: container` on the call line or the line above marks a site
    # whose CONTAINER owns the box — an absolute-inset img, an aspect-ratio
    # frame — so the call site cannot shift layout and carries no pair.
    RESERVED_MARKER = "reserved: container"

    def image_findings
      views = Dir.glob(File.join(RAILS_ROOT, "{brgen,amber,bsdports,shared}/app/views/**/*.erb")) +
              Dir.glob(File.join(RAILS_ROOT, "brgen/engines/*/app/views/**/*.erb"))
      views.flat_map do |path|
        lines = File.read(path, encoding: "UTF-8").lines
        lines.each_with_index.filter_map do |line, idx|
          next if line.lstrip.start_with?("<%#")
          next unless line.match?(IMAGE_CALL)
          next if line.match?(/width|height|aspect|size:/)
          next if line.include?(RESERVED_MARKER) || (idx.positive? && lines[idx - 1].include?(RESERVED_MARKER))
          Finding.new("unreserved_image", path.sub("#{RAILS_ROOT}/", ""), "line #{idx + 1}")
        end
      end
    end

    # --- accent scope ---------------------------------------------------------

    # brgen's verticals are mountable engines, so a glob at brgen/app/** reads
    # the host and none of the six. This one did, and reported 0 over a third of
    # its own subject: `.market-hero-kicker` and `.deal-rating` were outside it,
    # and the first is the site design_tokens.yml names when it explains why the
    # taupe accent cannot be darkened. image_findings above was widened for this
    # reason already; accent_findings was not.
    #
    # brgen only, and that is the rule rather than the glob. The rationale is
    # brgen's grayscale identity — "the direction itself, not a rotated hue"
    # (_root.scss) — so a hue on prose spends the surface's one accent. amber's
    # identity IS its warm taupe, and its `.sustainability-grade` and
    # `.weather-bar` are that identity rather than debt. Widening to amber would
    # apply brgen's rule to a surface it was never written for.
    def accent_findings
      brgen_bundle_sources.flat_map do |path|
        src = File.read(path, encoding: "UTF-8")
        src.each_line.with_index(1).filter_map do |line, n|
          next unless line.match?(/(?<!-)color:\s*var\(--accent\)/)
          selector = nearest_selector(src, n)
          next if selector.nil? || selector.match?(INTERACTIVE_SELECTOR)
          Finding.new("accent_on_prose", path.sub("#{RAILS_ROOT}/", ""), "line #{n} under #{selector.strip[0, 60]}")
        end
      end
    end

    # The bundle, not the directory. accent_on_prose is a claim about brgen's
    # grayscale identity, and brgen's bundle is not brgen's stylesheet folder:
    # _stack_brgen forwards eleven shared partials and application.scss @uses
    # several more by bare name, so a shared file painting accent on prose lands
    # in brgen while sitting outside every glob this check used to have.
    # _nearby_chat_widget.scss is one, and it is correct — the accent is on a
    # link — but nothing here could say so.
    #
    # It also has to be the bundle rather than every shared file, because the
    # rule does not govern the other two dialects. amber is luxury and bsdports
    # is a green terminal; accent on text may be their identity and is not
    # brgen's to judge. _minimal.scss is the case that proves the distinction:
    # _stack_brgen does not forward it, so its .price reaches amber and bsdports
    # and never brgen.
    def brgen_bundle_sources
      load_paths = [ File.join(RAILS_ROOT, "brgen/app/assets/stylesheets"),
                     File.join(RAILS_ROOT, "shared/app/assets/stylesheets") ] +
                   Dir.glob(File.join(RAILS_ROOT, "brgen/engines/*/app/assets/stylesheets"))
      seen = []
      queue = [ File.join(RAILS_ROOT, "brgen/app/assets/stylesheets/application.scss") ]
      until queue.empty?
        path = queue.shift
        next if path.nil? || seen.include?(path) || !File.file?(path)

        seen << path
        File.read(path, encoding: "UTF-8").scan(/@(?:use|forward)\s+["']([^"']+)["']/) do |(target)|
          queue << resolve_partial(target, load_paths)
        end
      end
      seen
    end

    def resolve_partial(target, load_paths)
      dir = File.dirname(target)
      base = File.basename(target).delete_prefix("_")
      load_paths.filter_map { |root|
        [ "_#{base}.scss", "#{base}.scss" ]
          .map { |name| File.expand_path(File.join(root, dir, name)) }.find { |p| File.file?(p) }
      }.first
    end

    # The whole selector group, not its last line. `.widget-empty a,\n.widget-cta
    # {` is one selector and the `a` in its first member is what makes the accent
    # on it correct; reading only the line carrying the brace made this check
    # blind to every multi-line group in the tree.
    def nearest_selector(src, line_number)
      lines = src.lines[0...line_number]
      brace = lines.rindex { |l| l.match?(/^\s*[^@\s\/][^{]*\{/) }
      return nil if brace.nil?

      first = brace
      first -= 1 while first.positive? && lines[first - 1].match?(/,\s*\z/)
      lines[first..brace].join(" ")
    end

    # --- button vocabulary ----------------------------------------------------

    # The closed set (2026-08-21 consolidation): base + four variants + two
    # rare utilities. The zen-era btn--primary BEM twins died in the same
    # pass; any new spelling is the next schism at birth.
    # btn-share is its own pill (share control on marketplace/tv/nearby), not a
    # variant of the base — in the vocabulary because it is worn and styled.
    BTN_VOCABULARY = %w[btn btn-primary btn-ghost btn-danger btn-sm btn-link btn-block btn-share].to_set

    def btn_findings
      views = Dir.glob(File.join(RAILS_ROOT, "{brgen,amber,bsdports,shared}/app/views/**/*.erb")) +
              Dir.glob(File.join(RAILS_ROOT, "brgen/engines/*/app/views/**/*.erb"))
      views.flat_map do |path|
        File.read(path, encoding: "UTF-8").each_line.with_index(1).filter_map do |line, n|
          stray = line.scan(/\bbtn--?[\w-]+/).uniq.reject { |c| BTN_VOCABULARY.include?(c) }
          next if stray.empty?
          Finding.new("btn_vocabulary", path.sub("#{RAILS_ROOT}/", ""), "line #{n}: #{stray.join(" ")}")
        end
      end
    end

    # --- compose costume ------------------------------------------------------

    def costume_findings
      path = File.join(RAILS_ROOT, "brgen/app/assets/stylesheets/_chrome_surfaces.scss")
      return [] unless File.file?(path)

      src = File.read(path, encoding: "UTF-8")
      src.scan(/^([^{\n]*\.city-today[^{\n]*)\{([^}]*)\}/m).filter_map do |(selector, body)|
        next unless costume?(selector, body)

        Finding.new("compose_costume", "brgen/app/assets/stylesheets/_chrome_surfaces.scss",
                    "#{selector.strip} wears the compose pill again")
      end
    end

    # The costume is the PILL, not a tap target.
    #
    # This matched /radius-pill|tap-min/ under any .city-today selector, which
    # made it fire on `.city-today summary { min-height: var(--tap-min, 44px) }`
    # — a disclosure toggle, a real control, raised to the 44px Fitts floor by
    # 01e14ffa6 ("link lists were 20px tall where the floor is 44"). Two correct
    # rules in collision: ux_laws.fitts says a control takes a real target, and
    # this said a reading surface must not dress as the writing control. The
    # detector could not tell them apart, so the honest fix is the detector.
    #
    # A tap target on a DESCENDANT control is legitimate and always was. On the
    # strip itself it is not: the strip is a card, it is not pressable, and a
    # 44px minimum there is the compose pill's shape arriving by another name.
    # radius-pill stays a costume marker wherever it appears, because nothing
    # under this strip has any business being pill-shaped.
    def costume?(selector, body)
      return true if body.match?(/radius-pill/)
      return false unless body.match?(/tap-min/)

      # The strip itself — `.city-today` or `aside.city-today`, no descendant.
      selector.strip.split(",").any? { |part| part.strip.match?(/\A[a-z]*\.city-today\z/) }
    end
  end
end

exit(Operator::VisualContractLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
