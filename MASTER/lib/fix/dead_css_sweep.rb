# frozen_string_literal: true

require "fileutils"
require "json"
require "set"
require "yaml"
require_relative "scss_parser"
require_relative "dead_css_static"
require_relative "dead_css_coverage"
require_relative "dead_route_sweep"

module Master
  module Fix
    # Dead CSS, proven twice. A rule is dead when rendered coverage (every
    # captured surface, viewport and state of the app) never matched it AND the
    # static scan finds no class or id it requires named anywhere in the source.
    # One proof alone is advisory: coverage misses states nobody opened, and the
    # static scan misses names composed in ways it cannot read.
    #
    #   dead     both proofs        -> the only class `apply` may remove
    #   static   static only        -> advisory (no coverage data for the rule)
    #   state    coverage only      -> informational; styled states nobody opened
    #
    # Nothing here deletes unless `apply` is called, and apply works on one app,
    # leaf rules only, through WriteGuard and a Transaction.
    class DeadCssSweep
      LAW = "DEAD_CSS"
      ROUTE_LAW = "DEAD_ROUTE"
      Verdict = Data.define(:rule, :kind, :unnamed, :judged)

      attr_reader :root, :out_dir

      def initialize(root: File.expand_path("../../..", __dir__), out_dir: DeadCssCoverage::DIR)
        @root = root
        @out_dir = out_dir
      end

      def rails = File.join(root, "RAILS")
      def shared_root = File.join(rails, "__shared")

      def app_names
        YAML.safe_load_file(File.join(rails, "apps.yml"), aliases: true).fetch("apps").keys.map(&:to_s).sort
      end

      # app => { rules:, verdicts:, summary: }; "__shared" is judged against
      # every app's coverage and every app's source.
      def run(apps: app_names + ["__shared"])
        apps.to_h { |app| [app, analyse(app)] }
      end

      def findings(results)
        results.flat_map do |app, res|
          res[:verdicts].select { |v| %i[dead static].include?(v.kind) }.map do |v|
            { law: LAW, severity: :info, advisory: true, app:, file: rel(v.rule.file), line: v.rule.line,
              selector: v.rule.selectors.join(", "), evidence: v.kind == :dead ? "coverage+static" : "static only",
              message: "#{v.rule.selectors.join(", ")} requires #{v.unnamed.join(" ")} which nothing names" }
          end
        end
      end

      def route_findings(shared_text: "")
        roots = (app_names.to_h { |a| [a, File.join(rails, a)] }).merge(engine_roots)
        DeadRouteSweep.new(app_roots: roots, shared_root:, corpus_text: shared_text).candidates.map do |c|
          { law: ROUTE_LAW, severity: :info, advisory: true, app: c.app, kind: c.kind, subject: c.subject, message: c.detail }
        end
      end

      def write_report(results, findings)
        FileUtils.mkdir_p(out_dir)
        summary = results.transform_values { |r| r[:summary] }
        File.write(File.join(out_dir, "report.json"), JSON.pretty_generate(summary:, findings:))
        File.write(File.join(out_dir, "report.txt"), text(summary, findings))
        File.join(out_dir, "report.txt")
      end

      # Removes the `dead` leaf rules of one app. Returns { removed:, files:, error: }.
      def apply(app, results: nil)
        res = (results || run(apps: [app])).fetch(app)
        return { removed: 0, files: [], error: "no rendered coverage for #{app}; refusing to delete on one proof" } if res[:summary][:coverage_surfaces].zero?

        dead = res[:verdicts].select { |v| v.kind == :dead && v.rule.leaf }
        by_file = dead.group_by { |v| v.rule.file }
        return { removed: 0, files: [], error: nil } if by_file.empty?

        write_files(app, by_file)
      end

      private

      def analyse(app)
        sheets = sheet_files(app)
        rules = sheets.flat_map { |f| ScssRules.parse(File.read(f, encoding: "UTF-8"), file: f) }
        static = DeadCssStatic.new(roots: corpus_roots(app), extra_text: sheets.map { |f| File.read(f, encoding: "UTF-8") })
        coverage = coverage_for(app)
        verdicts = rules.reject(&:dynamic).map { |rule| verdict(rule, static, coverage["selectors"]) }
        { rules:, verdicts:, summary: summary(app, sheets, rules, verdicts, coverage, static) }
      end

      def verdict(rule, static, covered)
        rows = rule.selectors.map do |sel|
          names = ScssRules.required_names(sel)
          [static.unnamed(names), covered[ScssRules.normalize(sel)]]
        end
        unnamed = rows.flat_map(&:first).uniq
        statically_dead = rows.all? { |u, _| !u.empty? }
        covers = rows.map(&:last)
        kind = if statically_dead && covers.all?(false) then :dead
               elsif statically_dead then :static
               elsif covers.all?(false) then :state
               else :live
               end
        Verdict.new(rule:, kind:, unnamed:, judged: rows.any? { |u, c| !u.empty? || !c.nil? })
      end

      def summary(app, sheets, rules, verdicts, coverage, static)
        count = ->(kind) { verdicts.count { |v| v.kind == kind } }
        dead_lines = verdicts.select { |v| %i[dead static].include?(v.kind) }.flat_map { |v| (v.rule.line..v.rule.end_line).to_a }.to_set
        total_lines = sheets.sum { |f| File.foreach(f).count }
        { app:, stylesheets: sheets.map { |f| rel(f) }, rules_total: rules.size, rules_judged: verdicts.size,
          dead: count.(:dead), static_only: count.(:static), state_only: count.(:state),
          lines_total: total_lines, lines_dead_estimate: dead_lines.size,
          dead_share_pct: total_lines.zero? ? 0.0 : (100.0 * dead_lines.size / total_lines).round(1),
          coverage_surfaces: Array(coverage["surfaces"]).size, corpus_files: static.files,
          basis: Array(coverage["surfaces"]).empty? ? "static scan only; rendered coverage unverified" : "coverage+static" }
      end

      def sheet_files(app)
        dirs = app == "brgen" ? [File.join(rails, "brgen"), *engine_roots.values] : [File.join(rails, app)]
        dirs.flat_map { |d| Dir.glob(File.join(d, "app", "assets", "stylesheets", "**", "*.{scss,css}")) }.sort
      end

      def engine_roots
        # brgen_radio holds two engines one level down (playlist, tv).
        dirs = Dir.glob(File.join(rails, "brgen_*")) + Dir.glob(File.join(rails, "brgen_*", "*"))
        dirs.select { |d| File.directory?(File.join(d, "app")) }.to_h { |d| [d.delete_prefix(rails + "/"), d] }
      end

      # The engine's CSS is judged against the apps that mount it; master does not,
      # so a class only its face names cannot keep a shared rule alive.
      def corpus_roots(app)
        all = app_names.reject { |a| standalone?(a) }.map { |a| File.join(rails, a) } + engine_roots.values
        return [*all, shared_root] if app == "__shared"

        [File.join(rails, app), shared_root, *(app == "brgen" ? engine_roots.values : [])]
      end

      def standalone?(app)
        gemfile = File.join(rails, app, "Gemfile")
        File.file?(gemfile) && !File.read(gemfile).include?('gem "pub4-shared"')
      end

      # "__shared" is used when any app rendered it.
      def coverage_for(app)
        return DeadCssCoverage.load(app, dir: out_dir) unless app == "__shared"

        merged = { "surfaces" => [], "selectors" => {} }
        app_names.each do |a|
          data = DeadCssCoverage.load(a, dir: out_dir)
          merged["surfaces"] |= data["surfaces"].map { |s| "#{a}:#{s}" }
          data["selectors"].each { |sel, used| merged["selectors"][sel] = merged["selectors"][sel] || used }
        end
        merged
      end

      def write_files(app, by_file)
        require_relative "transaction"
        require_relative "write_guard"
        edits = by_file.to_h { |file, vs| [file, cut(File.read(file, encoding: "UTF-8"), vs.map(&:rule))] }
        txn = Transaction.new(root:, paths: edits.keys.map { |f| rel_root(f) }, id: "dead-css-#{app}-#{Time.now.to_i}").begin!
        edits.each do |file, content|
          verdict = WriteGuard.default.verdict(path: file, content:)
          raise "WriteGuard refused #{rel(file)}: #{verdict.reason}" if verdict.blocked?

          File.write(file, content)
        end
        txn.finalize!
        { removed: by_file.values.sum(&:size), files: edits.keys.map { |f| rel(f) }, error: nil }
      rescue StandardError => e
        txn&.rollback!
        { removed: 0, files: [], error: "#{e.class}: #{e.message}" }
      end

      # The source with each rule's span removed, whole lines when the rule owns them.
      def cut(source, rules)
        out = source.dup
        rules.sort_by(&:start).reverse_each do |r|
          from = r.start
          from -= 1 while from.positive? && out[from - 1].match?(/[ \t]/)
          from = r.start unless from.zero? || out[from - 1] == "\n"
          to = r.stop
          to += 1 while out[to]&.match?(/[ \t]/)
          to += 1 if out[to] == "\n"
          to += 1 if out[to] == "\n" && (from.zero? || out[from - 1] == "\n")
          out[from...to] = ""
        end
        out
      end

      def text(summary, findings)
        lines = ["dead css and routes sweep (advisory; nothing deleted)", ""]
        summary.each_value do |s|
          lines << format("%-10s rules=%d dead=%d static_only=%d state_only=%d dead_share=%.1f%% (%s)",
                          s[:app], s[:rules_total], s[:dead], s[:static_only], s[:state_only], s[:dead_share_pct], s[:basis])
        end
        lines << ""
        findings.each do |f|
          lines << (f[:law] == LAW ? "#{f[:law]} #{f[:app]} #{f[:file]}:#{f[:line]} #{f[:message]} [#{f[:evidence]}]" : "#{f[:law]} #{f[:app]} #{f[:subject]} #{f[:message]}")
        end
        lines.join("\n") + "\n"
      end

      def rel(path) = path.to_s.delete_prefix(root + "/")
      alias rel_root rel
    end
  end
end
