# frozen_string_literal: true

require "rbconfig"
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
#   MASTER/bin/pub4 measure            # fast: pure-Ruby lints + declared ceilings
#   MASTER/bin/pub4 measure --deep     # + the scans that cost minutes
#   MASTER/bin/pub4 measure --json
#   MASTER/bin/pub4 measure --why <row>    the members behind one number
#   MASTER/bin/pub4 measure --since <ref>  every recorded ceiling's delta
#
# --why exists because a bare integer cannot be acted on. "OVER +826" names no
# file, so a session that has just moved a ceiling cannot tell whether the move
# is its own. Every row that can enumerate its population now carries it, and it
# carries the SAME list the count came from rather than a second reading of the
# same census — a member list computed a second way buys a disagreement, which
# is the defect this whole file exists to catch.
#
# --since reads the recorded ceilings out of git rather than re-running the
# census at another commit. Re-running needs a checkout of that commit, and a
# detached worktree cannot `require "master"` (measured 2026-08-15; the note on
# Row#ok? below is what that cost). The ceilings ARE the record: nearly every
# row in this register sits exactly at its ceiling, so the ceiling at <ref> is
# the value at <ref>, and `git show` answers it for the price of a subprocess.
#
# Fast means "reads files"; deep means "runs a scanner". The one exception is a
# batched `git check-ignore` per tree, four subprocesses that cost milliseconds
# and answer a question no amount of file reading can: which paths on disk this
# repository already considers disposable. Fast mode stays cheap enough to run
# before every commit.

require "json"
require "yaml"

module Pub4
  module Ratchets
    ROOT = File.expand_path("../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    RUBY = RbConfig.ruby
    MASTER = File.join(ROOT, "MASTER")

    # name, current, ceiling, and how to read it again. `direction` is what the
    # number is allowed to do: :down for a ratchet, :fixed for an invariant.
    #
    # `members` is the population the number counts, carried out of the same call
    # that produced the count. Not recomputed on demand: a member list read a
    # second way is a second implementation of the measurement, and this file
    # exists because two of those disagreed (see file_length_rows below). A row
    # that genuinely cannot enumerate itself leaves it nil and --why says so.
    Row = Struct.new(:name, :current, :ceiling, :direction, :source, :note, :members, keyword_init: true) do
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
      rows = spine_rows + master_yaml_rows + rails_lint_rows + pub4_growth_rows +
             entrypoint_rows + file_length_rows + coverage_rows
      # The placeholders only when the real numbers are not being fetched, or
      # every css_budget rule would appear twice under --deep.
      rows += deep ? css_constitution_rows : css_budget_rows
      rows += deep_rows if deep
      rows.compact
    end

    # Rules that reach no detector, and files that declare no namespace. Both
    # recompute the current value rather than reading the recorded one twice —
    # a row whose current IS its ceiling is a row that can never fail, which is
    # the shape of defect the rest of this file exists to catch.
    def master_yaml_rows
      [master_row("rule_reach", "data/rules.yml", "rules no configuration can run") do
         require File.join(MASTER, "tools/rule_reach")
         unreachable = Pub4::RuleReach.unreachable
         [unreachable.size, Pub4::RuleReach.ceiling, unreachable]
       end,
       # Three rows rather than one, because they are three different facts and
       # collapsing them would let a rule go blind while another stops being
       # silent and the total holds still.
       master_row("rule_audit.blind", "data/rules.yml", "rules proved on input their subjects never get") do
         require File.join(MASTER, "tools/rule_audit")
         blind = Pub4::RuleAudit.audit[:fixture_blindness]
         [blind.size, Pub4::RuleAudit.ceilings.fetch("blind"), blind.map { |row| "#{row[:rule]}: #{row[:detail]}" }]
       end,
       master_row("rule_audit.saturated", "data/rules.yml", "rules flagging most of what they read") do
         require File.join(MASTER, "tools/rule_audit")
         saturated = Pub4::RuleAudit.audit[:saturation]
         [saturated.size, Pub4::RuleAudit.ceilings.fetch("saturated"),
          saturated.map { |row| format("%s: %d/%d files", row[:rule], row[:hits], row[:applicable]) }]
       end,
       master_row("rule_audit.silent", "data/rules.yml", "rules firing on nothing in the corpus") do
         require File.join(MASTER, "tools/rule_audit")
         silent = Pub4::RuleAudit.audit[:silent]
         [silent.size, Pub4::RuleAudit.ceilings.fetch("silent"), silent]
       end,
       master_row("autofix_reach.dangling", "data/autofix_reach.yml", "rules naming a transform nothing implements") do
         require File.join(MASTER, "tools/autofix_reach")
         dangling = Pub4::AutofixReach.dangling
         [dangling.size, Pub4::AutofixReach.ceilings.fetch("dangling"),
          dangling.map { |row| "#{row[:id]} -> #{row[:transform]}" }]
       end,
       master_row("autofix_reach.bare_true", "data/autofix_reach.yml", "rules claiming a fix without naming it") do
         require File.join(MASTER, "tools/autofix_reach")
         bare = Pub4::AutofixReach.bare_true
         [bare.size, Pub4::AutofixReach.ceilings.fetch("bare_true"), bare]
       end,
       master_row("rule_hygiene.id_case_collisions", "data/rules.yml", "ids differing only by case") do
         require File.join(MASTER, "tools/rule_hygiene")
         collisions = Pub4::RuleHygiene.report[:id_case_collisions]
         [collisions.size, Pub4::RuleHygiene.ceilings.fetch("id_case_collisions"), collisions.map(&:to_s)]
       end,
       master_row("rule_hygiene.alias_shadows_live_rule", "data/rules.yml", "aliases naming a rule that still exists") do
         require File.join(MASTER, "tools/rule_hygiene")
         shadows = Pub4::RuleHygiene.report[:alias_shadows_live_rule]
         [shadows.size, Pub4::RuleHygiene.ceilings.fetch("alias_shadows_live_rule"), shadows.map(&:to_s)]
       end,
       master_row("rule_hygiene.missing_metadata", "data/rules.yml", "rules with neither tier nor severity") do
         require File.join(MASTER, "tools/rule_hygiene")
         missing = Pub4::RuleHygiene.report[:missing_metadata]
         [missing.size, Pub4::RuleHygiene.ceilings.fetch("missing_metadata"), missing.map(&:to_s)]
       end,
       master_row("rule_hygiene.cross_population_duplicates", "data/rules.yml", "one id with two detectors") do
         require File.join(MASTER, "tools/rule_hygiene")
         duplicates = Pub4::RuleHygiene.report[:cross_population_duplicates]
         [duplicates.size, Pub4::RuleHygiene.ceilings.fetch("cross_population_duplicates"), duplicates.map(&:to_s)]
       end,
       master_row("rule_hygiene.statement_conflicts", "data/rules.yml", "one id, two statements") do
         require File.join(MASTER, "tools/rule_hygiene")
         conflicts = Pub4::RuleHygiene.report[:statement_conflicts]
         [conflicts.size, Pub4::RuleHygiene.ceilings.fetch("statement_conflicts"), conflicts.map(&:to_s)]
       end,
       # The fourth hygiene check and the dep graph both reported a number that
       # nothing failed on. rule_hygiene warned on its own ceiling and ratchets
       # never carried the row; RuleRegistryAudit reported dep_graph_gaps and no
       # ceiling anywhere read it.
       master_row("rule_fixture_debt", "data/rules.yml", "registry rules with no worked example") do
         $LOAD_PATH.unshift(File.join(MASTER, "lib")) unless $LOAD_PATH.include?(File.join(MASTER, "lib"))
         require "master"
         require "review/scan/rule_dsl"
         unfixtured = Master::Review::Scan::Rule.registry.reject do |klass|
           (klass.respond_to?(:dsl_fires) && (klass.dsl_fires || klass.dsl_does_not_fire)) ||
             !klass.respond_to?(:dsl_block)
         end
         [unfixtured.size, Master.law("rule_ratchets", root: MASTER).dig("fixture_debt", "without_fixtures"),
          unfixtured.map(&:name)]
       end,
       master_row("rule_deps.ungraphed", "data/rules.yml", "registry rules absent from rule_deps") do
         $LOAD_PATH.unshift(File.join(MASTER, "lib")) unless $LOAD_PATH.include?(File.join(MASTER, "lib"))
         require "master"
         audit = Master::Review::Scan::RuleRegistryAudit.new(root: MASTER)
         ungraphed = audit.ungraphed_rule_ids
         [ungraphed.size, Master.law("rule_ratchets", root: MASTER).dig("deps", "ungraphed"), ungraphed.map(&:to_s)]
       end,
       master_row("self_findings.law", "data/self_findings.yml", "what the 122 laws find in our own trees") do
         require File.join(MASTER, "tools/self_findings")
         found = Pub4::SelfFindings.members
         [found.size, Pub4::SelfFindings.ceiling, found]
       end,
       # The second population. The row above read "what our own rules find in
       # our own trees" and counted the law alone, so nothing in this repo
       # counted the 145 rules the scanner builds: rule_audit runs them over a
       # sixth of the tree and measures blindness, and bin/pub4 gate runs them
       # over all four trees and records nothing.
       master_row("self_findings.registry", "data/self_findings.yml",
                  "what the scanner's own rules find, at error severity") do
         require File.join(MASTER, "tools/self_findings")
         found = Pub4::SelfFindings.registry_members
         [found.size, Pub4::SelfFindings.registry_ceiling, found]
       end,
       master_row("dup_census", "data/dup_census.yml", "tracked files existing twice") do
         require File.join(MASTER, "tools/dup_census")
         sets = Pub4::DupCensus.sets
         [sets.size, Pub4::DupCensus.ceiling, Pub4::DupCensus.members(sets)]
       end,
       master_row("data_reach", "data/data_reach.yml", "data keys no code names") do
         require File.join(MASTER, "tools/data_reach")
         unnamed = Pub4::DataReach.unnamed
         [unnamed.size, Pub4::DataReach.ceiling, unnamed]
       end,
       # Sibling to data_reach, one level up: that asks whether a declaration
       # has a reader, this whether a whole file does. It reads 0 and the row
       # exists to hold it there — an unreached file is how lib/ grows without
       # anything failing.
       master_row("code_reach", "data/code_reach.yml", "lib files nothing names") do
         require File.join(MASTER, "tools/code_reach")
         unreached = Pub4::CodeReach.unreached
         [unreached.size, Pub4::CodeReach.ceiling, unreached]
       end,
       master_row("namespace", "data/namespace_ceilings.yml", "files declaring no module or class") do
         require File.join(MASTER, "tools/namespace_ratchet")
         flat = Pub4::NamespaceRatchet.ceilings.keys.flat_map { |dir| Pub4::NamespaceRatchet.flat_files(dir) }
         [flat.size, Pub4::NamespaceRatchet.ceilings.values.sum, flat]
       end,
       *%w[lone_dirs stutter vague_names].map do |kind|
         master_row("sprawl.#{kind}", "data/sprawl_census.yml", "the shape of the tree, in all four of them") do
           require File.join(MASTER, "tools/sprawl_census")
           [Pub4::SprawlCensus.counts.fetch(kind), Pub4::SprawlCensus.ceilings.fetch(kind),
            Array(Pub4::SprawlCensus.public_send(kind))]
         end
       end].compact
    end

    # A block may return [current, ceiling] or [current, ceiling, members]; the
    # third slot is the population the count came from, so --why reads the same
    # list rather than asking the census again.
    def master_row(name, relative, note)
      return unless File.file?(File.join(MASTER, relative))

      current, ceiling, members = yield
      Row.new(name:, current:, ceiling:, direction: :down,
              source: "MASTER/#{relative}", note:, members:)
    rescue StandardError => e
      Row.new(name:, current: nil, ceiling: nil, direction: :down,
              source: "MASTER/#{relative}", note: "unreadable: #{e.class}")
    end

    # MASTER: the spine ratchet, read from data/spine.yml.

    def spine_rows
      spine = YAML.safe_load_file(File.join(MASTER, "data/spine.yml")).fetch("spine")
      [
        Row.new(name: "spine.lib_body_ceiling", current: lib_code_lines, ceiling: spine["lib_body_ceiling"],
                direction: :down, source: "MASTER/data/spine.yml",
                note: "a budget with a sponsor, not a promise (DECISIONS.md)"),
        Row.new(name: "spine.core_files",
                current: core_files.size, members: core_files,
                ceiling: spine["core_files"], direction: :fixed, source: "MASTER/data/spine.yml",
                note: "the actual invariant: a new top-level concept is a design change"),
      ]
    rescue StandardError => e
      [Row.new(name: "spine", current: nil, ceiling: nil, direction: :down,
               source: "MASTER/data/spine.yml", note: "unreadable: #{e.class}")]
    end

    def core_files
      Dir.glob(File.join(MASTER, "lib/{core.rb,core/*.rb}")).map { |path| relative_to_root(path) }.sort
    end

    # Same definition as the Rakefile's lint:spine: non-blank, non-comment.
    # The same counter lint:spine uses, rather than a second copy of it. This
    # register exists because ten instruments each had their own idea of where
    # the number lived; carrying its own line count would have made eleven.
    def lib_code_lines
      $LOAD_PATH.unshift(File.join(MASTER, "lib")) unless $LOAD_PATH.include?(File.join(MASTER, "lib"))
      require "master"
      Master::Review::Scan::CodeMetrics.body_lines_in(File.join(MASTER, "lib"))
    end

    # pub4-wide sprawl guard: a source-file ceiling per tree, read from the same
    # spine.yml. A new file anywhere puts a tree OVER and fails; a deletion puts
    # it SLACK and also fails, so a win only lands when its ceiling is lowered to
    # lock it — the exact discipline that keeps sprawl from regrowing into slack.
    # Pure Ruby, so it stays in fast mode and runs before every commit.
    # The population is what git tracks, not what is on disk. This checkout is
    # shared and a working-tree walk charged one session for another's
    # uncommitted files — an untracked stems render raised growth.studio against
    # a session that had never opened STUDIO. Tracking is also the honest moment
    # for this row: a file joins the tree when it is committed. entrypoint_count
    # has asked git all along, and this is the same question.
    # TREE_EXCLUDE keeps what git tracks that is still not ours to count --
    # vendored JavaScript, compiled asset builds, dilla's project state and its
    # committed renders. It has to stay a regex because a name-shaped clause
    # cannot catch a sidecar sitting at a tree's root, and every clause added to
    # try shadowed something real: `log` hid lib/trace/log/, three tracked Ruby
    # files the census never saw.
    TREE_EXCLUDE = %r{/(\.git|node_modules|tmp|renders|[\w.-]*stems|samples|scratch|project|crate|venv|\.venv|site-packages|vendor|storage|\.cache|builds|coverage|\.master|knowledge|output)/|/public/assets/|\.wav\.quality\.json\z}
    TREE_SOURCE_EXT = %w[.rb .rake .erb .scss .css .js .mjs .yml .yaml .md .sh .ksh .exp .html .json].freeze

    def pub4_growth_rows
      ceilings = YAML.safe_load_file(File.join(MASTER, "data/spine.yml")).fetch("pub4_source_ceilings")
      ceilings.map do |tree, ceiling|
        files = tree_source_files(tree)
        Row.new(name: "growth.#{tree.downcase}", current: files.size,
                ceiling:, direction: :down, source: "MASTER/data/spine.yml",
                note: "tracked source files; a new file folds in or raises this",
                members: files)
      end
    rescue StandardError => e
      [Row.new(name: "growth", current: nil, ceiling: nil, direction: :down,
               source: "MASTER/data/spine.yml", note: "unreadable: #{e.class}")]
    end

    # The count CLAUDE.md's "two surfaces, no third" asserts. It was prose, so it
    # rotted from 2 to 28 in silence; this is the reader that makes it fail.
    # Executables directly under a tree's own bin/, so a Rails app's generated
    # bin/rails and a STUDIO tool's private bin/ are not mistaken for surfaces.
    def entrypoint_rows
      ceilings = YAML.safe_load_file(File.join(MASTER, "data/spine.yml")).fetch("pub4_entrypoint_ceilings")
      ceilings.map do |tree, ceiling|
        doors = entrypoints(tree)
        Row.new(name: "entrypoints.#{tree.downcase}", current: doors&.size,
                ceiling:, direction: :down, source: "MASTER/data/spine.yml",
                note: "commands the tree offers; folding one in is how this falls",
                members: doors)
      end
    rescue StandardError => e
      [Row.new(name: "entrypoints", current: nil, ceiling: nil, direction: :down,
               source: "MASTER/data/spine.yml", note: "unreadable: #{e.class}")]
    end

    # Tracked, not on-disk: an untracked script in a shared checkout is another
    # session's scratch and not a surface this repo offers anyone.
    def entrypoints(tree)
      out, status = Open3.capture2e("git", "-C", ROOT, "ls-files", "-z", "#{tree}/bin")
      return unless status.success?

      out.split("\0").select do |path|
        path.count("/") == 2 && File.executable?(File.join(ROOT, path))
      end.sort
    end

    def tree_source_files(tree)
      tracked_source_files.select { |path| path.start_with?("#{tree}/") }
    end

    # One call for all four trees, so this stays fast enough for a hook. Nothing
    # is rescued: a growth row measured without asking git what it tracks is the
    # blind instrument this file exists to catch, and pub4_growth_rows turns the
    # raise into an unreadable row, which fails.
    def tracked_source_files
      @tracked_source_files ||= begin
        out, status = Open3.capture2e("git", "-C", ROOT, "ls-files", "-z")
        raise "git ls-files failed: #{out}" unless status.success?

        out.split("\0").select do |path|
          "/#{path}" !~ TREE_EXCLUDE && TREE_SOURCE_EXT.include?(File.extname(path).downcase)
        end
      end
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
      "model_contract" => "shared/lib/pub4/model_contract_lint.rb",
      "destructive_action" => "shared/lib/pub4/destructive_action_lint.rb",
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

      # One scan, then grouped. The count and the member list come from the same
      # findings, so --why can never disagree with the number beside it — and the
      # scan is the expensive half, so asking twice would also cost twice.
      findings = mod.scan
      if mod.const_defined?(:BASELINES)
        by_kind = findings.group_by(&:kind)
        mod.const_get(:BASELINES).map do |kind, ceiling|
          hits = by_kind.fetch(kind, [])
          Row.new(name: "#{name}.#{kind}", current: hits.size, ceiling:,
                  direction: :down, source: relative_to_root(path), note: nil,
                  members: hits.map { |finding| describe_finding(finding) })
        end
      else
        Row.new(name:, current: findings.size, ceiling: mod.const_get(:BASELINE),
                direction: :down, source: relative_to_root(path), note: nil,
                members: findings.map { |finding| describe_finding(finding) })
      end
    rescue StandardError => e
      Row.new(name:, current: nil, ceiling: nil, direction: :down,
              source: relative_to_root(path), note: "unreadable: #{e.class}: #{e.message}")
    end

    # Eight lints, eight different Finding structs — file/line here, sheet/ref
    # there. The kind is already the row name, so what is left of the struct is
    # what identifies the member; joining it beats eight per-lint formatters.
    def describe_finding(finding)
      return finding.to_s unless finding.respond_to?(:to_h)

      finding.to_h.reject { |key, _| key == :kind }.values.compact.join(" ")
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
        Row.new(name: "css_budget.#{rule}", current: nil, ceiling:, direction: :down,
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

    # css_budget's seven rules, from one gate run.
    #
    # css_budget_rows above has said "current value is --deep (runs
    # css_constitution)" since it was written, and --deep did not run it: the
    # four rows in deep_rows below are selftest, selfcheck, principle_trace and
    # design_baseline. So the register's own note described a reader that did
    # not exist, and the seven rules it covers stayed `?` in every mode.
    #
    # That matters more than a blank column. On 2026-08-25 four RAILS ratchets
    # were red at once and `measure` could not see any of the CSS ones — the
    # tool whose whole purpose is "every ratchet, current beside recorded" was
    # blind exactly where the failures were, which is how they accumulated
    # without anyone noticing they had.
    #
    # One invocation for all seven, not seven: the gate walks 94 stylesheets and
    # running it per rule would turn a slow command into an unusable one.
    def css_constitution_rows
      ceilings = css_budget_ceilings
      return [] if ceilings.empty?

      # Both gates, because the seven rules are split across them: rhythm,
      # important, magic_hex, type_scale and weight_ladder come from
      # css_constitution, and the two contrast rules from design_metrics. The
      # ceilings all live in one file, which is what made them look like one
      # gate's business.
      output = %w[css_constitution design_metrics].map do |gate|
        Open3.capture2e(RUBY, "gates/runner.rb", gate, chdir: RAILS).first
      end.join("\n")

      ceilings.map do |rule, ceiling|
        # The SUMMARY line, not the first line that happens to name the rule.
        #
        # css_constitution prints one line per finding before its total —
        # "rhythm: brgen/.../_canvas.scss:21 120px" — so matching any line
        # mentioning the rule picked a file path and read no number from it.
        # rhythm was the one rule with findings to print, so it was the one rule
        # this got wrong, which is the shape a looser regex always has.
        #
        # Three spellings, all of them the gates' own:
        #   "rule: 59, under its 66 ceiling (-7)"   passing with slack
        #   "rule: 91 exceeds ceiling 90 (+1)"      over
        #   "rule: at its 0 ceiling"                exactly on it
        name = Regexp.escape(rule)
        summary = output.lines.find do |candidate|
          candidate.match?(/#{name}: (?:\d+,? (?:under|exceeds)|at its \d+ ceiling)/)
        end
        current = if summary.nil?
                    nil
                  elsif summary.match?(/#{name}: at its \d+ ceiling/)
                    summary[/#{name}: at its (\d+) ceiling/, 1].to_i
                  else
                    summary[/#{name}: (\d+)/, 1]&.to_i
                  end
        Row.new(name: "css_budget.#{rule}", current:, ceiling:, direction: :down,
                source: "RAILS: gates/runner.rb css_constitution",
                note: current.nil? ? "neither gate printed a count for #{rule} (silent when it passes)" : nil)
      end
    end

    def css_budget_ceilings
      path = File.join(RAILS, "gates/data/css_budget.yml")
      return {} unless File.file?(path)

      YAML.safe_load_file(path).fetch("rules")
    end

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
      Row.new(name:, current:, ceiling:, direction: :down,
              source: "#{dir}: #{command}",
              note: ceiling.nil? ? "no recorded ceiling — see TODO.md" : nil)
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
                  "measure: #{rows.count(&:ok?)} ratchet(s) at their recorded value"
                else
                  "measure: #{broken.size} off — #{broken.map(&:name).join(', ')}"
                end
      (["ratchet".ljust(width) + "  current / ceiling  state"] + lines + ["", summary]).join("\n")
    end

    # --why: the members behind one number.
    #
    # A prefix match, because the row names are long and the useful ones are
    # families — `--why sprawl` answers all three at once, `--why growth.rails`
    # answers one. Naming nothing lists the rows that can answer, which is the
    # question a reader has before they have a row name.
    def why(rows, query)
      return why_index(rows, query).join("\n") if query.to_s.empty?

      matched = rows.select { |row| row.name == query }
      matched = rows.select { |row| row.name.start_with?(query) } if matched.empty?
      return why_index(rows, query).join("\n") if matched.empty?

      matched.flat_map { |row| why_row(row) }.join("\n")
    end

    def why_index(rows, query)
      answerable = rows.select(&:members)
      head = query.to_s.empty? ? "measure --why <row>" : "measure --why: no row named #{query.inspect}"
      lines = [head, "", "#{answerable.size} of #{rows.size} rows can name their members:"]
      lines + answerable.map { |row| "  #{row.name}" }
    end

    def why_row(row)
      head = "#{row.name}  #{row.current || '?'} / #{row.ceiling || '-'}  #{row.state}  (#{row.source})"
      return [head, "  this row records a count and no population — nothing to name", ""] if row.members.nil?

      body = row.members.map { |member| "  #{member}" }
      # The instrument checking itself. A member list whose length is not the
      # number printed beside it means the count and the population came apart,
      # and a register that cannot notice that is the register this file replaced.
      unless row.members.size == row.current
        body << "  MISMATCH: #{row.members.size} member(s) listed against a count of #{row.current}"
      end
      [head] + body + [""]
    end

    # --since: what this session did to the recorded ceilings.
    #
    # The ceilings are files in git, so the delta is `git show <ref>:<path>`
    # against the working copy — no checkout, no second census, and it works from
    # a worktree. It answers about the RECORD rather than about the tree: a row
    # whose current value drifted without its ceiling moving shows as unchanged
    # here and OVER in the table above, which are two different facts and both
    # worth having.
    def since(ref, rows = all)
      sources = rows.filter_map { |row| row.source if row.source.to_s.end_with?(".yml") }.uniq.sort
      lines = ["measure --since #{ref}: recorded ceilings, then against now", ""]
      moved = sources.flat_map { |source| ceiling_deltas(ref, source) }
      lines << if moved.empty?
                 "  no recorded ceiling moved in #{sources.size} file(s) since #{ref}"
               else
                 moved.join("\n")
               end
      lines.join("\n")
    end

    def ceiling_deltas(ref, source)
      before, status = Open3.capture2e("git", "-C", ROOT, "show", "#{ref}:#{source}")
      return ["  #{source}: not at #{ref} (#{before.lines.first&.chomp})"] unless status.success?

      was = numeric_leaves(YAML.safe_load(before, aliases: true))
      now = numeric_leaves(YAML.safe_load_file(File.join(ROOT, source), aliases: true))
      (was.keys | now.keys).sort.filter_map do |key|
        old = was[key]
        new = now[key]
        next if old == new

        delta = old && new ? format("%+d", new - old) : "added or removed"
        "  #{source} #{key}: #{old || '-'} -> #{new || '-'} (#{delta})"
      end
    rescue Psych::Exception => e
      ["  #{source}: unparseable at #{ref} or now (#{e.class})"]
    end

    # Every integer in the document, keyed by its dotted path. Generic on
    # purpose: the ceilings live under a different key in every one of these
    # files, and a per-file reader would be twelve readers to maintain.
    def numeric_leaves(node, prefix = nil, into = {})
      case node
      when Hash
        node.each { |key, value| numeric_leaves(value, [prefix, key].compact.join("."), into) }
      when Integer
        into[prefix] = node
      end
      into
    end

    def json(rows)
      JSON.pretty_generate(rows.map do |row|
        { name: row.name, current: row.current, ceiling: row.ceiling,
          direction: row.direction, state: row.state, source: row.source, note: row.note,
          members: row.members }
      end)
    end

    # Non-zero when any readable ratchet is over OR slack. Slack counts because a
    # ceiling above the real number is room the next change grows into silently.
    def ok?(rows)
      rows.none? { |row| !row.current.nil? && !row.ceiling.nil? && !row.ok? }
    end
  end
end
