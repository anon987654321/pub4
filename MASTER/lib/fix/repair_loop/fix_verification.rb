# frozen_string_literal: true

require "pathname"
require_relative "../../operator/ruby_runner"
require_relative "../rails_app"

module Master
  module Fix
    class RepairLoop
      # Staleness/verification checks run before and after we apply a fix
      # (fingerprint drift, missing test coverage) — separate from RepairLoop's
      # own scan/prompt/apply pipeline.
      module FixVerification
        def fingerprint_matches?(violation)
          stored = violation[:fingerprint] || violation["fingerprint"]
          return true if stored.to_s.empty?
          return false unless File.file?(violation[:file].to_s)

          current = semantic_fingerprint_for(violation[:file].to_s)
          return true if current == stored.to_s

          @bus&.publish(
            "repair_loop:stale_scan", law: @law.id, file: violation[:file], expected: stored, actual: current
          )
          false
        end

        # A control for the semantic check (MASTER_FIX_SCAN_AGREEMENT=1): the unchanged file is scanned once
        # more and the two scans compared, mechanical and semantic findings apart, so how often the
        # semantic stream disagrees with itself is measured instead of assumed. One extra scan per repair.
        # A diagnostic of the scanner itself: the unchanged file scanned a second time. Asked for with
        # MASTER_FIX_SCAN_AGREEMENT=1; by default it cost one more full scan of every repaired file.
        def log_scan_agreement(path, first)
          return unless ENV["MASTER_FIX_SCAN_AGREEMENT"] == "1"

          line = scan_agreement_line(File.basename(path.to_s), first, scan_all(path))
          Master::Trace::Dmesg.status("fix0", line)
          @bus&.publish("repair_loop:scan_agreement", law: @law.id, file: path, summary: line)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "repair_loop.scan_agreement", event_bus: @bus, path:)
        end

        def scan_agreement_line(name, first, second)
          ids = mechanical_law_ids
          split = ->(rows) { ids.empty? ? [rows, []] : rows.partition { |row| ids.include?(row[:law].to_s) } }
          mech1, sem1 = split.call(first)
          mech2, sem2 = split.call(second)
          laws = ->(rows) { rows.map { |row| row[:law].to_s }.tally }
          a = laws.call(sem1)
          b = laws.call(sem2)
          gained = (a.keys | b.keys).to_h { |law| [law, b.fetch(law, 0) - a.fetch(law, 0)] }.reject { |_, n| n.zero? }
          same = laws.call(mech1) == laws.call(mech2) ? "same" : "DIFFERENT"
          "scan agreement #{name}: mechanical #{mech1.size} vs #{mech2.size} #{same}; semantic #{sem1.size} vs #{sem2.size}" \
            "#{gained.empty? ? " same laws" : " (second minus first: #{gained.map { |law, n| "#{law} #{n.positive? ? "+" : ""}#{n}" }.join(", ")})"}"
        end

        # The findings the new-violations check counts. The semantic stream (an LLM reading the file) names
        # its findings freely: RATE_LIMITING_MISSING, NO_CHANGELOG_COMMENT and MERGE_BEFORE_MULTIPLY are in
        # no registry, and two scans of one file need not agree on them, so a rejection on their count can
        # be noise. The default reads them loosely: only findings of registered mechanical laws are counted,
        # and what the semantic stream added is logged, not gated; the reflexion verifier still reads the
        # change itself. MASTER_FIX_SEMANTIC_CHECK=strict counts every finding.
        def check_findings(rows)
          return rows if strict_semantic_check?

          ids = mechanical_law_ids
          rows = rows.reject { |row| model_read?(row) }
          ids.empty? ? rows : rows.select { |row| ids.include?(row[:law].to_s) }
        end

        # The scan marks what a model's reading found (Scan::FileProcessor#from_the_model).
        def model_read?(row) = row.is_a?(Hash) && row[:stream] == :semantic

        def strict_semantic_check? = ENV.fetch("MASTER_FIX_SEMANTIC_CHECK", "loose") == "strict"

        # What the semantic stream added by a repair, named in the log so a loose check is still visible.
        def note_semantic_drift(path, raw_before, raw_after)
          return if strict_semantic_check?

          ids = mechanical_law_ids
          return if ids.empty?

          laws = lambda do |rows|
            rows.select { |row| model_read?(row) || !ids.include?(row[:law].to_s) }.map { |row| row[:law].to_s }.tally
          end
          was = laws.call(raw_before)
          added = laws.call(raw_after).filter_map { |law, n| "#{law} +#{n - was.fetch(law, 0)}" if n > was.fetch(law, 0) }
          return if added.empty?

          Master::Trace::Dmesg.status("fix0", "semantic findings noted, not gated: #{File.basename(path.to_s)} #{added.first(4).join(", ")}")
        end

        def mechanical_law_ids
          laws = @scanner.respond_to?(:laws) ? Array(@scanner.laws) : []
          laws.reject { |law| semantic_stream_law?(law) }.map { |law| law.id.to_s }.to_set
        end

        def semantic_stream_law?(law)
          semantic = defined?(Master::Review::Scan::Laws::SemanticLaw) && Master::Review::Scan::Laws::SemanticLaw
          (semantic && law.is_a?(semantic)) || law.respond_to?(:set_agent) || law.id.to_s == "semantic"
        end

        # What a rejected repair added, by law, so the retry can be told what to avoid
        # instead of only that "new_violations" happened: "ABC_SIZE +1 (line 12); STRONG_PARAMETERS +2 (line 4, 9)".
        # With the repaired source the first offending line is quoted, so the retry sees the code itself.
        def introduced_summary(before, after, source: nil, limit: 3)
          text = source.to_s.lines
          had = law_counts(before)
          added = introduced_findings(before, after).group_by { |row| row[:law].to_s }.map do |law, rows|
            grown = rows.size - had.fetch(law, 0)
            numbers = rows.filter_map { |row| row[:line] }.uniq.first(3)
            quoted = text[numbers.first.to_i - 1].to_s.strip[0, 70] if numbers.any?
            where = numbers.empty? ? "" : " (line #{numbers.join(", ")}#{quoted.to_s.empty? ? "" : ": `#{quoted}`"})"
            "#{law} +#{grown}#{where}"
          end
          added.first(limit).join("; ")
        end

        # Every finding of each law whose count the repair grew. "New" is counted per law, not
        # matched by message: messages carry the numbers they measure ("ABC size 43.0"), so a
        # refactor that eased a finding read as a new one. The summary and boyscout share it.
        def introduced_findings(before, after)
          had = law_counts(before)
          grown = law_counts(after).select { |law, count| count > had.fetch(law, 0) }
          after.select { |row| grown.key?(row[:law].to_s) }
        end

        def law_counts(rows) = rows.map { |row| row[:law].to_s }.tally

        def note_unverified_fix(violation)
          return if test_file_for(violation[:file]).any?

          @bus&.publish(
            "repair_loop:fix_unverified", rule: @law.id, file: violation[:file], note: "fix unverified — add test"
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "repair_loop.note_unverified_fix", event_bus: @bus)
          nil
        end

        # The file's own test, run once the fix is on disk. The rescan proves the
        # rule stopped firing; only the test proves the behaviour survived it.
        # Named exactly, test_<stem>.rb, because test_file_for's loose match finds
        # every test sharing a common stem. nil means the test passed or there
        # is none; a string names the failure.
        def failing_test_for(path)
          app, test = FixVerification.rails_test_for(File.expand_path(path.to_s, @root))
          return run_rails_test(app, test) if test

          test = own_test_for(path)
          return unless test

          suite = File.dirname(File.dirname(test))
          run_own_test(own_test_command(suite, test), suite:, test:)
        end

        def run_own_test(command, suite:, test:)
          out, status = Master::Io::Exec.capture2e(*command, chdir: suite)
          status.success? ? nil : "#{File.basename(test)}: #{out.lines.last(3).join.strip}"
        end

        # Under the app's own Ruby and bundle (RailsApp.capture), not MASTER's: run from inside
        # MASTER, bin/rails inherited BUNDLE_GEMFILE and stopped on bootsnap/setup, so every repair
        # to an app file with a test was refused for a test that never ran.
        def run_rails_test(app, test)
          out, status = RailsApp.capture(app, "bin/rails", "test", test, env: { "RAILS_ENV" => "test" })
          status.success? ? nil : "#{File.basename(test)}: #{out.lines.last(3).join.strip}"
        end

        # Run as the suite runs it: lib/ and test/ on the load path, so
        # test_helper loads, and through the bundle when the suite has one.
        # A suite with no Gemfile has no bundle to run under, and `bundle exec`
        # there fails with "Could not locate Gemfile" whatever the fix.
        # MASTER's own suite runs in the bundle this process already holds, by its own interpreter and
        # environment: `bundle exec` picked rbenv's bundler, which ran Homebrew's Ruby against MASTER's
        # gem store and failed in rubygems before test_doctor.rb loaded.
        def own_test_command(suite, test)
          ruby = [RbConfig.ruby, "-Ilib", "-Itest", test]
          own = File.expand_path(suite) == File.expand_path(Master::ROOT)
          return ruby if own || !File.file?(File.join(suite, "Gemfile"))

          [::Operator::RubyRunner.bundle_cmd(root: @root), "exec", *ruby]
        end

        # A Rails file's test follows the Rails layout: app/models/user.rb is tested by
        # test/models/user_test.rb beside the same app/. An engine (RAILS/brgen_dating,
        # RAILS/brgen_radio/tv) and the shared engine have no bin/rails of their own; they
        # run inside brgen, which mounts them and whose suite already holds their tests.
        # Answers [app root, test path relative to it].
        RAILS_FILE = %r{\A(?<rails>.+/RAILS)/(?<component>.+?)/app/(?<kind>[^/]+)/(?<rest>.+)\.rb\z}
        MOUNTED_BY = "brgen"

        def self.rails_test_for(path)
          found = path.to_s.match(RAILS_FILE)
          return unless found

          component = File.join(found[:rails], found[:component])
          test = File.join(component, "test", found[:kind], "#{found[:rest]}_test.rb")
          app = File.file?(File.join(component, "bin", "rails")) ? component : File.join(found[:rails], MOUNTED_BY)
          return unless File.file?(test) && File.file?(File.join(app, "bin", "rails"))

          [app, Pathname(test).relative_path_from(Pathname(app)).to_s]
        end

        def own_test_for(path)
          name = "test_#{File.basename(path.to_s, File.extname(path.to_s))}.rb"
          test_file_for(path).find { |file| File.basename(file) == name }
        end

        # Delegates rather than computes: Review::Scan::SemanticFingerprint.for
        # stamps the fingerprint this compares against, and two copies of one
        # formula disagree the moment either gains a field. That module's own
        # comment holds what the disagreement cost.
        def semantic_fingerprint_for(path)
          src = File.read(path, encoding: "UTF-8")
          Master::Review::Scan::SemanticFingerprint.for(src)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "repair_loop.semantic_fingerprint", event_bus: @bus, path:)
          ""
        end

        def test_file_for(path)
          rel = path.to_s.delete_prefix("#{@root}/")
          stem = File.basename(rel, File.extname(rel))
          patterns = [
            File.join(@root, "test", "**", "*#{stem}*.rb"),
            File.join(@root, "MASTER", "test", "**", "*#{stem}*.rb"),
          ]
          patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq.select { |file| File.file?(file) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "repair_loop.test_file_for", event_bus: @bus, path:)
          raise "repair_loop: test discovery failed for #{path}: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
