# frozen_string_literal: true

require "open3"

# Every ratchet in the repo, in one place, with its current value beside its
# recorded one.
#
# The truth was spread across ten instruments — rake selftest, rake selfcheck,
# lint:spine, four Pub4::*Lint modules, gates/data/css_budget.yml,
# coverage_ratchet_test.rb and file_length_ratchet_test.rb — each with its own
# invocation and its own idea of where the number lives. On 2026-08-11 four of
# them were stale and were found by accident, one at a time, while doing unrelated
# work. A register nobody can read in one pass is a register nobody reads.
#
# Two failures, not one. A ratchet is broken when the current value is ABOVE its
# ceiling (new debt) and equally when it is BELOW and the ceiling was never
# lowered (slack the next change grows into without failing anything). Only
# chrome_i18n_lint tested for the second; this makes it the contract for all of
# them.
#
#   bin/pub4 measure            # fast: pure-Ruby lints + declared ceilings
#   bin/pub4 measure --deep     # + the scans that cost minutes
#   bin/pub4 measure --json
#
# Fast means "reads files"; deep means "runs a scanner". Nothing here shells out
# in fast mode, so it is cheap enough to run before every commit.

require "json"
require "yaml"

module Pub4
  module Ratchets
    ROOT = File.expand_path("../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    MASTER = File.join(ROOT, "MASTER")

    # name, current, ceiling, and how to read it again. `direction` is what the
    # number is allowed to do: :down for a ratchet, :fixed for an invariant.
    Row = Struct.new(:name, :current, :ceiling, :direction, :source, :note, keyword_init: true) do
      def over? = current && ceiling && current > ceiling
      def slack? = current && ceiling && current < ceiling

      def state
        return "unreadable" if current.nil?
        return "OVER +#{current - ceiling}" if over?
        return "SLACK -#{ceiling - current}" if slack?

        "at"
      end

      # An unreadable ratchet is not a passing ratchet.
      #
      # `state` has always had a word for `current.nil?` — "unreadable" — while
      # `ok?` said `!over? && !slack?`, and both of those are false when there is
      # no number, so a row that could not be measured reported as fine. That is
      # the shape of every defect this file exists to catch: the instrument goes
      # blind and the gate goes green. Seen 2026-08-15 running the ratchets from
      # a detached worktree, where `require "master"` does not resolve and the
      # spine row vanished from the output entirely rather than failing.
      def ok? = !current.nil? && !over? && !slack?
    end

    module_function

    def all(deep: false)
      rows = spine_rows + master_yaml_rows + rails_lint_rows + css_budget_rows +
             file_length_rows + coverage_rows
      rows += deep_rows if deep
      rows.compact
    end

    # Rules that reach no detector, and files that declare no namespace. Both
    # recompute the current value rather than reading the recorded one twice —
    # a row whose current IS its ceiling is a row that can never fail, which is
    # the shape of defect the rest of this file exists to catch.
    def master_yaml_rows
      [master_row("rule_reach", "data/rule_reach.yml", "rules no configuration can run") do
         require File.join(MASTER, "tools/rule_reach")
         [Pub4::RuleReach.unreachable.size, YAML.safe_load_file(File.join(MASTER, "data/rule_reach.yml")).fetch("unreachable")]
       end,
       master_row("data_reach", "data/data_reach.yml", "data keys no code names") do
         require File.join(MASTER, "tools/data_reach")
         [Pub4::DataReach.unnamed.size, Pub4::DataReach.ceiling]
       end,
       master_row("namespace", "data/namespace_ceilings.yml", "files declaring no module or class") do
         require File.join(MASTER, "tools/namespace_ratchet")
         [Pub4::NamespaceRatchet.measure.values.sum, Pub4::NamespaceRatchet.ceilings.values.sum]
       end].compact
    end

    def master_row(name, relative, note)
      return nil unless File.file?(File.join(MASTER, relative))

      current, ceiling = yield
      Row.new(name: name, current: current, ceiling: ceiling, direction: :down,
              source: "MASTER/#{relative}", note: note)
    rescue StandardError => e
      Row.new(name: name, current: nil, ceiling: nil, direction: :down,
              source: "MASTER/#{relative}", note: "unreadable: #{e.class}")
    end

    # MASTER: the spine ratchet, read from data/spine.yml.

    def spine_rows
      spine = YAML.safe_load_file(File.join(MASTER, "data/spine.yml")).fetch("spine")
      [
        Row.new(name: "spine.lib_code_ceiling", current: lib_code_lines, ceiling: spine["lib_code_ceiling"],
                direction: :down, source: "MASTER/data/spine.yml",
                note: "a budget with a sponsor, not a promise (DECISIONS.md)"),
        Row.new(name: "spine.core_files", current: Dir.glob(File.join(MASTER, "lib/{core.rb,core/*.rb}")).size,
                ceiling: spine["core_files"], direction: :fixed, source: "MASTER/data/spine.yml",
                note: "the actual invariant: a new top-level concept is a design change"),
      ]
    rescue StandardError => e
      [Row.new(name: "spine", current: nil, ceiling: nil, direction: :down,
               source: "MASTER/data/spine.yml", note: "unreadable: #{e.class}")]
    end

    # Same definition as the Rakefile's lint:spine: non-blank, non-comment.
    # The same counter lint:spine uses, rather than a second copy of it. This
    # register exists because ten instruments each had their own idea of where
    # the number lived; carrying its own line count would have made eleven.
    def lib_code_lines
      $LOAD_PATH.unshift(File.join(MASTER, "lib")) unless $LOAD_PATH.include?(File.join(MASTER, "lib"))
      require "master"
      Master::Review::Scan::CodeMetrics.code_lines_in(File.join(MASTER, "lib"))
    end

    # The RAILS lints, each a Pub4 module with its own BASELINES.

    # Each is a module with BASELINES (per kind) or BASELINE (single) and a scan.
    RAILS_LINTS = {
      "chrome_i18n" => "shared/lib/pub4/chrome_i18n_lint.rb",
      "breakpoint" => "shared/lib/pub4/breakpoint_lint.rb",
      "empty_state" => "shared/lib/pub4/empty_state_lint.rb",
      "css_coverage" => "shared/lib/pub4/css_coverage_lint.rb",
      "asset_url" => "shared/lib/pub4/asset_url_lint.rb",
      "visual_contract" => "shared/lib/pub4/visual_contract_lint.rb",
    }.freeze

    def rails_lint_rows
      RAILS_LINTS.flat_map do |name, relative|
        path = File.join(RAILS, relative)
        next [] unless File.file?(path)

        rows_for_lint(name, path)
      end
    end

    def rows_for_lint(name, path)
      require path
      mod = lint_module(path)
      return [] unless mod

      if mod.const_defined?(:BASELINES)
        counts = mod.counts
        mod.const_get(:BASELINES).map do |kind, ceiling|
          Row.new(name: "#{name}.#{kind}", current: counts[kind], ceiling: ceiling,
                  direction: :down, source: relative_to_root(path), note: nil)
        end
      else
        Row.new(name: name, current: mod.scan.size, ceiling: mod.const_get(:BASELINE),
                direction: :down, source: relative_to_root(path), note: nil)
      end
    rescue StandardError => e
      Row.new(name: name, current: nil, ceiling: nil, direction: :down,
              source: relative_to_root(path), note: "unreadable: #{e.class}: #{e.message}")
    end

    # Pub4::ChromeI18nLint from chrome_i18n_lint.rb, without guessing at names.
    def lint_module(path)
      constant = File.basename(path, ".rb").split("_").map(&:capitalize).join
      Pub4.const_get(constant) if Pub4.const_defined?(constant)
    end

    # Ceilings that live in gates/data rather than in a lint.

    # css_budget's numbers need the gate to run (it compiles nothing, but it does
    # walk 94 stylesheets), so the ceiling is read here and the current value is
    # deep-only.
    def css_budget_rows
      path = File.join(RAILS, "gates/data/css_budget.yml")
      return [] unless File.file?(path)

      YAML.safe_load_file(path).fetch("rules").map do |rule, ceiling|
        Row.new(name: "css_budget.#{rule}", current: nil, ceiling: ceiling, direction: :down,
                source: "RAILS/gates/data/css_budget.yml",
                note: "current value is --deep (runs css_constitution)")
      end
    end

    # Ceilings a test file owns.

    # POINTED AT, NOT RE-MEASURED — and the first version of this method is why.
    #
    # It scraped the `"path" => number` pairs out of the test and compared them
    # against File.readlines(...).size, and reported 19 entries off their ceiling.
    # Every one was a false positive: those ceilings are CODE lines (non-blank,
    # non-comment, block comments stripped per language) and raw lines are a
    # different number. A second implementation of a measurement disagreeing with
    # the first is the exact failure this whole file exists to prevent, so the rule
    # is now explicit: a ratchet whose own test already checks BOTH directions is
    # listed here as a pointer. Re-implementing it buys a disagreement, not a check.
    def file_length_rows
      path = File.join(RAILS, "test/file_length_ratchet_test.rb")
      return [] unless File.file?(path)

      [Row.new(name: "file_length", current: nil, ceiling: nil, direction: :down,
               source: "RAILS/test/file_length_ratchet_test.rb",
               note: "code lines, per language; its own test fails over AND slack")]
    end

    # coverage_ratchet keeps per-app floors; these are FLOORS, so the direction is
    # up and "slack" means the tree improved without the floor being raised.
    def coverage_rows
      path = File.join(RAILS, "test/coverage_ratchet_test.rb")
      return [] unless File.file?(path)

      [Row.new(name: "coverage_ratchet", current: nil, ceiling: nil, direction: :up,
               source: "RAILS/test/coverage_ratchet_test.rb",
               note: "floors, not ceilings — run the test; it fails in both directions already")]
    end

    # Deep rows: these shell out to a scanner and cost minutes.

    def deep_rows
      [
        shell_row("selftest", "MASTER", "bundle exec rake selftest", /self-test: (\d+) violation/, 0),
        shell_row("selfcheck", "MASTER", "bundle exec rake selfcheck", /selfcheck: (\d+) violation/, nil),
        # Deep because the rule registry is global and a suite run has test-defined
        # rules in it: measured in-process it reads high and fails a green tree.
        shell_row("principle_trace", "MASTER", "bundle exec rake lint:principle_trace",
                  /principle_trace: (\d+)[\/ ]/, 101),
        # Deep because it scans every RAILS view and stylesheet with the full
        # design rule set — the layout campaign's ratchet (2026-08-21).
        shell_row("design_baseline", "MASTER", "bundle exec ruby tools/design_baseline.rb",
                  /design_baseline: (\d+) violation/,
                  YAML.safe_load_file(File.join(MASTER, "data/design_baseline.yml")).fetch("total", nil)),
      ].compact
    end

    def shell_row(name, dir, command, pattern, ceiling)
      # The commands in deep_rows are fixed literals with no quoting, so the
      # split is faithful; the arg-array form keeps the shell out entirely.
      output, _status = Open3.capture2e(*command.split, chdir: File.join(ROOT, dir))
      current = output[pattern, 1]&.to_i
      Row.new(name: name, current: current, ceiling: ceiling, direction: :down,
              source: "#{dir}: #{command}",
              note: ceiling.nil? ? "no recorded ceiling — see MASTER/DEBT.md" : nil)
    end

    def relative_to_root(path)
      path.sub("#{ROOT}/", "")
    end

    # Rendering.

    def render(rows)
      width = rows.map { |row| row.name.length }.max
      lines = rows.map do |row|
        current = row.current.nil? ? "?" : row.current.to_s
        ceiling = row.ceiling.nil? ? "-" : row.ceiling.to_s
        line = format("  %-#{width}s %8s / %-8s %-10s", row.name, current, ceiling, row.state)
        row.note ? "#{line} #{row.note}" : line
      end
      broken = rows.reject(&:ok?).reject { |row| row.current.nil? || row.ceiling.nil? }
      summary = if broken.empty?
                  "measure: #{rows.count { |r| r.ok? }} ratchet(s) at their recorded value"
                else
                  "measure: #{broken.size} off — #{broken.map(&:name).join(', ')}"
                end
      (["ratchet".ljust(width) + "  current / ceiling  state"] + lines + ["", summary]).join("\n")
    end

    def json(rows)
      JSON.pretty_generate(rows.map do |row|
        { name: row.name, current: row.current, ceiling: row.ceiling,
          direction: row.direction, state: row.state, source: row.source, note: row.note }
      end)
    end

    # Non-zero when any readable ratchet is over OR slack. Slack counts because a
    # ceiling above the real number is room the next change grows into silently.
    def ok?(rows)
      rows.none? { |row| !row.current.nil? && !row.ceiling.nil? && !row.ok? }
    end
  end
end

