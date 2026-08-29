# frozen_string_literal: true

require_relative "baseline_ratchet"

require "yaml"

module Pub4
  # Ratchet: every media-query width must be one of design_tokens.yml's `viewport`
  # edges, or that edge minus 1px for a max-width bound.
  #
  # Colour, space, motion, elevation and the dialect maps are all single-sourced;
  # breakpoints were the one axis that was not, and they drifted the way an
  # unmeasured axis always does — 13 distinct widths across 58 queries, including
  # three spellings of one edge.
  #
  # Two kinds, because they are not the same defect:
  #
  #   unknown_edge   — a width that is not in the token list at all. Cosmetic drift
  #                    until two of them disagree about the same edge.
  #   ambiguous_edge — one number used as BOTH a max bound and a min bound
  #                    somewhere in the tree. At exactly that width both blocks
  #                    match, so which one wins is source order rather than intent.
  #
  # The second kind is deliberately a property of the tree and not of the line. A
  # first version flagged every `max-width` equal to a token edge and reported 14,
  # which is not a defect: `(max-width: 768px)` with `(min-width: 769px)` is a
  # correct scheme, and so is `(max-width: 767px)` with `(min-width: 768px)`. This
  # tree uses both. The bug is only ever the collision.
  #
  # Same contract as empty_state_lint and chrome_i18n_lint: baseline per kind,
  # never raised to silence a new finding. Opt out one line with
  # `// breakpoint: ok` on it or the line above.
  module BreakpointLint
    RAILS_ROOT = File.expand_path("../../..", __dir__)
    TOKENS = File.join(RAILS_ROOT, "shared", "design_tokens.yml")
    OPT_OUT = "breakpoint: ok"

    # (min-width: 768px) / (max-width: 47.9375rem) / (min-device-width: 480px)
    QUERY = /\((?<bound>min|max)-(?:device-)?width:\s*(?<value>[\d.]+)(?<unit>px|rem|em)\)/

    # Generated bundles, vendored copies and precompiled artifacts are not source.
    # public/assets in particular holds pre-rename copies of files that no longer
    # exist, so scanning it reports last month's stylesheet as today's drift.
    SKIP = %r{/(node_modules|vendor|builds|public/assets|tmp)/}

    # Measured 2026-08-11.
    #
    # ambiguous_edge was 26 sites over three numbers — 640, 768 and 1265 were each
    # both a floor and a ceiling somewhere in the family, so at exactly those three
    # widths two blocks matched and bundle order decided. Closed by moving the six
    # colliding max-bounds down one pixel, which keeps the interpretation the
    # min-width author had already declared. It is a ratchet at zero now, not a
    # tolerance: the next collision is a new one.
    #
    # unknown_edge is 0 as of 2026-08-15, down from 3. The three that were "design
    # decisions rather than typos" — 700px in brgen/_marketplace_nav_bar, 400px and
    # 600px in shared/_zen_shell — are gone from the sheets, so the tolerance that
    # existed for them is gone too. The next unrecognised width is a new one.
    #
    # A fourth, 769px in brgen/_root, was a genuine gap and is fixed: the compose
    # control's tablet band started one pixel above the edge the rest of the family
    # uses, so at exactly 768px it fell through to base styling while the shell
    # around it was already in its tablet band.
    # unknown_edge 0 -> 1 on 2026-08-16, and the raise is a correction rather
    # than a tolerance for something new.
    #
    # The note above said all three were gone from the sheets. Two of them never
    # were findings: `@container grid (min-width: 400px)` and `(min-width: 600px)`
    # in shared/_zen_shell are container queries, and a container query measures
    # the element's own container rather than the viewport, so neither number
    # means anything on this scale. QUERY matched them because the eight
    # characters are identical in both at-rules. See CONTAINER below.
    #
    # The third is real and is still there: `(max-width: 700px)` in
    # brgen/_marketplace_nav_bar:256, the band where the marketplace search takes
    # its own row. The family's tablet edge is 768, max-bound 767, so viewports
    # between 701 and 767 get the wide marketplace nav while every other surface
    # already treats them as a tablet. Moving it to 767 closes that and changes
    # what renders at those widths, which is an operator's decision and not a
    # lint's.
    BASELINES = { "unknown_edge" => 0, "ambiguous_edge" => 0 }.freeze

    Finding = Struct.new(:file, :line, :kind, :value)

    extend Pub4::BaselineRatchet

    module_function

    def edges
      @edges ||= begin
        viewport = YAML.safe_load_file(TOKENS).fetch("viewport")
        viewport.values.map { |value| Integer(value) }.sort
      end
    end

    # rem and em in a media query resolve against the browser's root size, which is
    # 16px regardless of what any element sets — this is the one place `rem` is not
    # affected by brgen's 18px root.
    def to_px(value, unit)
      unit == "px" ? value.to_f : value.to_f * 16
    end

    def stylesheets
      Dir.glob(File.join(RAILS_ROOT, "*/app/assets/stylesheets/**/*.{scss,css}")) +
        Dir.glob(File.join(RAILS_ROOT, "*/engines/*/app/assets/stylesheets/**/*.{scss,css}")) +
        Dir.glob(File.join(RAILS_ROOT, "shared/app/assets/stylesheets/**/*.{scss,css}"))
    end

    # Comments blanked, line numbering preserved.
    #
    # TODO.md, Scanner Conventions 1, walked into on the first run of this file:
    # shared/_responsive.scss opens with a paragraph explaining why a rule is NO
    # LONGER wrapped in `@media (max-width: 768px)`, and the lint reported that
    # sentence as a colliding bound. A check that reads its own documentation
    # produces a false alarm the next author "fixes" by deleting the explanation.
    def source_lines(path)
      raw = File.read(path, encoding: "UTF-8")
      raw = raw.gsub(%r{/\*.*?\*/}m) { |block| block.gsub(/[^\n]/, " ") }
      raw.gsub(%r{//[^\n]*}) { |line| " " * line.length }.lines
    end

    # `@container grid (min-width: 400px)` is not a breakpoint.
    #
    # A container query measures the element's own container, not the viewport,
    # so a card grid switching to a row at 400px of container width is a
    # component decision that can happen at any viewport size — 400 and 600 mean
    # nothing on the viewport scale and there is no edge for them to be wrong
    # against. QUERY matched them anyway, because `(min-width: 400px)` is the
    # same eight characters in both, and the lint reported two correct container
    # queries in _zen_shell as unrecognised viewport widths.
    #
    # That is the shape this repo's own TODO.md calls Scanner Convention 1 and
    # breakpoint_lint already learned once with comments: a check that reports
    # correct code gets the correct code changed. The header's note that the
    # three tolerated edges "are gone from the sheets" is true of one of them.
    CONTAINER = /@container\b/

    # Every media-query bound in the tree: [file, line, bound, pixels, spelling].
    def bounds
      stylesheets.uniq.sort.reject { |path| path =~ SKIP }.flat_map do |path|
        lines = source_lines(path)
        lines.each_with_index.flat_map do |line, index|
          next [] if opted_out?(lines, index)
          next [] if line.match?(CONTAINER)

          line.to_enum(:scan, QUERY).map { Regexp.last_match }.map do |match|
            [ rel(path), index + 1, match[:bound], to_px(match[:value], match[:unit]).round,
             "#{match[:value]}#{match[:unit]}" ]
          end
        end
      end
    end

    # A number that is both a floor somewhere and a ceiling somewhere else.
    def ambiguous_pixels(all = bounds)
      by_bound = all.group_by { |(_, _, bound, _, _)| bound }
      mins = by_bound.fetch("min", []).map { |(_, _, _, px, _)| px }.uniq
      maxes = by_bound.fetch("max", []).map { |(_, _, _, px, _)| px }.uniq
      (mins & maxes).sort
    end

    def scan
      all = bounds
      ambiguous = ambiguous_pixels(all)
      all.filter_map do |(file, line, bound, pixels, spelling)|
        kind = classify(bound, pixels, ambiguous)
        Finding.new(file, line, kind, spelling) if kind
      end
    end

    def classify(bound, pixels, ambiguous)
      return "ambiguous_edge" if ambiguous.include?(pixels)
      return nil if edges.include?(pixels)
      return nil if bound == "max" && edges.include?(pixels + 1)

      "unknown_edge"
    end

    def opted_out?(lines, index)
      lines[[ index - 1, 0 ].max..index].join.include?(OPT_OUT)
    end

    def rel(path)
      path.sub("#{RAILS_ROOT}/", "")
    end

    def run
      findings = scan
      counts(findings).each do |kind, count|
        baseline = BASELINES.fetch(kind)
        note = count < baseline ? " — under baseline, lower it" : ""
        puts "breakpoint_lint: #{kind} #{count} (baseline #{baseline})#{note}"
      end
      findings.each { |f| puts "  #{f.file}:#{f.line} [#{f.kind}] #{f.value}" }

      exceeded = over_baseline(findings)
      return true if exceeded.empty?

      warn "breakpoint_lint: exceeds baseline — #{exceeded.join("; ")}"
      warn "breakpoint_lint: use a design_tokens.yml viewport edge (max-width bounds are edge - 1px)"
      false
    end
  end
end

exit(Pub4::BreakpointLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
