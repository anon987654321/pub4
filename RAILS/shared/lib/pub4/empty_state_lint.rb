# frozen_string_literal: true

require_relative "baseline_ratchet"

module Pub4
  # Empty states, in both directions.
  #
  # missing_action — a shared/empty_state render that skips the action:/actions:
  # local the partial already supports. A rendered empty state with no next step
  # is a dead end (NO_DEAD_ENDS / rams_checklist.thorough), and 47 of 54 call
  # sites had exactly this gap when first audited 2026-07-21. Add
  # `<%# empty_state: no-action-ok %>` immediately above a call site to mark it
  # deliberately CTA-less.
  #
  # no_empty_state — an index view that iterates a collection and renders
  # nothing at all when the collection is empty: no shared/empty_state, no
  # emptiness guard of its own. A blank page is not a designed state
  # (DEGRADE_GRACEFULLY); a first-visit user sees the product at its emptiest,
  # so the emptiest render is the one that most needs design. Add
  # `<%# empty_state: coverage-ok %>` in the view to mark a surface that is
  # never legitimately empty (seeded reference data, redirect-guarded).
  #
  # Both are ratchets, not hard bars: the counts can never silently grow, and
  # they come down as gaps get designed. Never raise a number to make a failing
  # run pass.
  module EmptyStateLint
    RENDER_CALL = /render\s*\(?\s*(?:partial:\s*)?["']shared\/empty_state["'].*?%>/m
    OPT_OUT = "empty_state: no-action-ok"
    COVERAGE_OPT_OUT = "empty_state: coverage-ok"

    ITERATION = /\.each\b|\.each_with_index\b|render\s+(?:partial:\s*)?["'][^"']+["'],\s*collection:|render\s+@\w+|render\(\s*@\w+/
    EMPTINESS_GUARD = /\bempty\?|\bnone\?|\bany\?|\bblank\?|\bpresent\?|\bexists\?|shared\/empty_state/

    # missing_action zero since the 2026-07-31 vertical CTA pass and holds.
    # no_empty_state measured 2026-08-20, the day the scan first read engine
    # views at all — the */app/views glob had silently excluded engines/ since
    # the verticals moved (the same blind spot four scanners had in the
    # engines migration).
    BASELINES = { "missing_action" => 0, "no_empty_state" => 0 }.freeze

    Finding = Struct.new(:kind, :file, :line)

    extend Pub4::BaselineRatchet

    module_function

    def run
      findings = scan
      over = counts(findings).select { |kind, count| count > BASELINES.fetch(kind) }
      counts(findings).each do |kind, count|
        puts "empty_state_lint: #{kind} #{count} (baseline #{BASELINES.fetch(kind)})"
      end
      findings.each { |f| puts "  #{f.kind} #{f.file}:#{f.line}" }
      over.each { |kind, count| warn "empty_state_lint: #{kind} #{count} exceeds baseline #{BASELINES.fetch(kind)}" }
      over.empty?
    end

    def rails_root
      File.expand_path("../../..", __dir__) # RAILS/
    end

    def relative(path)
      path.sub("#{rails_root}/", "")
    end

    def view_files
      Dir.glob(File.join(rails_root, "*/app/views/**/*.erb")) +
        Dir.glob(File.join(rails_root, "brgen/engines/*/app/views/**/*.erb"))
    end

    def scan
      action_findings + coverage_findings
    end

    def action_findings
      findings = []
      view_files.each do |path|
        content = File.read(path, encoding: "UTF-8")
        content.to_enum(:scan, RENDER_CALL).each do
          match = Regexp.last_match
          call = match[0]
          next if call.include?("action:") || call.include?("actions:")

          line = content[0...match.begin(0)].count("\n") + 1
          preceding = content.lines[0...(line - 1)].last(2).join
          next if preceding.include?(OPT_OUT)

          findings << Finding.new("missing_action", relative(path), line)
        end
      end
      findings
    end

    def coverage_findings
      view_files.filter_map do |path|
        next unless File.basename(path) == "index.html.erb"

        content = File.read(path, encoding: "UTF-8")
        next if content.include?(COVERAGE_OPT_OUT)
        next unless content.match?(ITERATION)
        next if content.match?(EMPTINESS_GUARD)

        Finding.new("no_empty_state", relative(path), 1)
      end
    end
  end
end

exit(Pub4::EmptyStateLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
