# frozen_string_literal: true

module Pub4
  # The visual decisions that are law, made measurable. Four checks, one ratchet
  # each; every ceiling only descends.
  #
  #   low_contrast — WCAG ratios computed from the COMPILED bundles, because the
  #     build is what production wears (WIRING_NOTES: "read the second table
  #     before the first"). Text pairs need 4.5:1, UI/accent pairs 3:1.
  #     Custom properties are resolved one var() hop within the same bundle;
  #     pairs that don't resolve to hex are skipped, not guessed.
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

    TEXT_PAIRS = [%w[--text --bg], %w[--text-secondary --surface], %w[--text-secondary --bg]].freeze
    UI_PAIRS = [%w[--accent --bg], %w[--danger --bg]].freeze

    INTERACTIVE_SELECTOR = /\ba\b|button|\.btn|link|tab|chip|badge|action|:hover|:focus|active|vote|toggle|nav|pill|switch|control|icon|spinner|progress|ring|cursor|caret|brand|logo|accent/i

    # Measured 2026-08-20, first run. The three low_contrast rows are the
    # light-theme vertical accents (dating #00d4aa 1.91:1, playlist #12b6c4
    # 2.47:1, takeaway #e07b39 2.97:1 on #ffffff) — recorded debt: each needs
    # a darkened light-theme variant, a colour decision rather than a lint
    # edit. The accent_on_prose rows are named by running this file. Lower on
    # fix; never raise to silence.
    BASELINES = {
      "low_contrast" => 3,
      "unreserved_image" => 33,
      "accent_on_prose" => 2,
      "compose_costume" => 0,
    }.freeze

    Finding = Struct.new(:kind, :file, :detail)

    module_function

    def scan
      contrast_findings + image_findings + accent_findings + costume_findings
    end

    def counts(findings = scan)
      BASELINES.keys.to_h { |kind| [kind, findings.count { |f| f.kind == kind }] }
    end

    def run
      findings = scan
      over = counts(findings).select { |kind, count| count > BASELINES.fetch(kind) }
      counts(findings).each { |kind, count| puts "visual_contract_lint: #{kind} #{count} (baseline #{BASELINES.fetch(kind)})" }
      findings.each { |f| puts "  #{f.kind} #{f.file}: #{f.detail}" }
      over.each { |kind, count| warn "visual_contract_lint: #{kind} #{count} exceeds baseline #{BASELINES.fetch(kind)}" }
      over.empty?
    end

    # --- contrast -------------------------------------------------------------

    def contrast_findings
      BUNDLES.flat_map do |app, rel|
        path = File.join(RAILS_ROOT, rel)
        next [] unless File.file?(path)

        css = File.read(path, encoding: "UTF-8")
        tokens = root_tokens(css)
        pairs = TEXT_PAIRS.map { |p| p + [4.5] } + UI_PAIRS.map { |p| p + [3.0] }
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

      css.scan(/body\.vertical-(\w+)[^{]*\{[^}]*?--accent:\s*(#\h{3,6})/m).filter_map do |vertical, hex|
        ratio = contrast_ratio(hex, surface)
        next unless ratio < 3.0
        Finding.new("low_contrast", rel, "vertical-#{vertical} accent #{hex} on #{surface} = #{ratio.round(2)}:1 (needs 3:1)")
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

    def ratio_for(tokens, fg_name, bg_name)
      fg = resolve(tokens, fg_name)
      bg = resolve(tokens, bg_name)
      fg && bg ? contrast_ratio(fg, bg) : nil
    end

    def contrast_ratio(hex_a, hex_b)
      la, lb = [relative_luminance(hex_a), relative_luminance(hex_b)].sort.reverse
      (la + 0.05) / (lb + 0.05)
    end

    def relative_luminance(hex)
      hex = hex.delete("#")
      hex = hex.chars.map { |c| c * 2 }.join if hex.size == 3
      r, g, b = [hex[0, 2], hex[2, 2], hex[4, 2]].map do |channel|
        c = channel.to_i(16) / 255.0
        c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
      end
      0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    # --- image reservation ----------------------------------------------------

    IMAGE_CALL = /(?:image_tag[ (]|<img\b)[^\n]*/

    def image_findings
      views = Dir.glob(File.join(RAILS_ROOT, "{brgen,amber,bsdports,shared}/app/views/**/*.erb")) +
              Dir.glob(File.join(RAILS_ROOT, "brgen/engines/*/app/views/**/*.erb"))
      views.flat_map do |path|
        File.read(path, encoding: "UTF-8").each_line.with_index(1).filter_map do |line, n|
          next unless line.match?(IMAGE_CALL)
          next if line.match?(/width|height|aspect|size:/)
          Finding.new("unreserved_image", path.sub("#{RAILS_ROOT}/", ""), "line #{n}")
        end
      end
    end

    # --- accent scope ---------------------------------------------------------

    def accent_findings
      Dir.glob(File.join(RAILS_ROOT, "brgen/app/assets/stylesheets/*.scss")).flat_map do |path|
        src = File.read(path, encoding: "UTF-8")
        src.each_line.with_index(1).filter_map do |line, n|
          next unless line.match?(/color:\s*var\(--accent\)/)
          selector = nearest_selector(src, n)
          next if selector.nil? || selector.match?(INTERACTIVE_SELECTOR)
          Finding.new("accent_on_prose", path.sub("#{RAILS_ROOT}/", ""), "line #{n} under #{selector.strip[0, 60]}")
        end
      end
    end

    def nearest_selector(src, line_number)
      src.lines[0...line_number].reverse_each.find { |l| l.match?(/^\s*[^@\s\/][^{]*\{/) }
    end

    # --- compose costume ------------------------------------------------------

    def costume_findings
      path = File.join(RAILS_ROOT, "brgen/app/assets/stylesheets/_chrome_surfaces.scss")
      return [] unless File.file?(path)

      src = File.read(path, encoding: "UTF-8")
      src.scan(/^[^{\n]*\.city-today[^{\n]*\{([^}]*)\}/m).filter_map do |(body)|
        next unless body.match?(/radius-pill|tap-min/)
        Finding.new("compose_costume", "brgen/app/assets/stylesheets/_chrome_surfaces.scss",
                    ".city-today wears the compose pill again")
      end
    end
  end
end

exit(Pub4::VisualContractLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
