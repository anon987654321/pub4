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

    INTERACTIVE_SELECTOR = /\ba\b|button|\.btn|link|tab|chip|badge|action|:hover|:focus|active|vote|toggle|nav|pill|switch|control|icon|spinner|progress|ring|cursor|caret|brand|logo|accent|input|select|textarea|summary/i

    # All four measured to 0 on 2026-08-21: the light-theme vertical accents
    # gained darkened same-hue variants, .price dropped the hue its bold
    # already carries, the image helpers reserve intrinsically and every raw
    # call site carries its pair or a reserved: container marker. Never raise
    # to silence.
    BASELINES = {
      "low_contrast" => 0,
      "unreserved_image" => 0,
      "accent_on_prose" => 0,
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

      winners = {}
      css.scan(/(?:body\.vertical-|:root\[data-theme="light"\] body\.vertical-)(\w+)[^{]*\{[^}]*?--accent:\s*(#\h{3,6})/m) do |vertical, hex|
        winners[vertical] = hex # last declaration wins, matching the cascade in light mode
      end
      winners.filter_map do |vertical, hex|
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
