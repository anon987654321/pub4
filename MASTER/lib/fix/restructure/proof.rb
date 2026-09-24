# frozen_string_literal: true

require "prism"

module Master
  module Fix
    class Restructure
      # What a restructure proves before it is kept. The Ruby it wrote parses;
      # MASTER still eager-loads, which is Zeitwerk checking that every path
      # defines the constant its name promises; the boot self-test finds no
      # ceiling breach it did not find before; and the tests that name what
      # moved fail no more than they did before the move.
      class Proof
        TEST_CAP = 20
        TIMEOUT_S = 600
        ENV_BOOT = { "MASTER_STRICT_BOOT" => "0", "MASTER_FAST" => "1" }.freeze

        def initialize(master_root:)
          @master = master_root
        end

        # Measured on the tree before the plan is applied.
        def baseline(plan)
          tests = related_tests(plan)
          { tests:, failing: failing(tests), breaches: }
        end

        # A reason the restructure fails, or nil.
        def failure(plan, before)
          parse_failure(plan) || load_failure || breach_failure(before) || test_failure(before)
        end

        private

        def parse_failure(plan)
          broken = plan.writes.keys.select { |path| path.end_with?(".rb", ".rake") }
                       .select { |path| Prism.parse_file(File.join(repo_root, path)).failure? }
          "Ruby does not parse: #{broken.join(", ")}" unless broken.empty?
        end

        def load_failure
          out, status = run(RbConfig.ruby, "-Ilib", "-e", 'require "master"; Master.eager_load!')
          "MASTER no longer eager-loads: #{out.lines.last(3).join.strip[0, 400]}" unless status.success?
        end

        def breach_failure(before)
          added = breaches - before[:breaches]
          "self-test ceiling breached: #{added.first(3).join("; ")}" unless added.empty?
        end

        def test_failure(before)
          added = failing(before[:tests]) - before[:failing]
          "tests now failing: #{added.join(", ")}" unless added.empty?
        end

        def breaches
          out, = run("rake", "selftest")
          out.lines.grep(/\(max \d+\)/).map { |line| line.strip.sub(%r{\A.*?/MASTER/}, "") }
        end

        def failing(tests)
          tests.reject do |test|
            _, status = run(RbConfig.ruby, "-Ilib", "-Itest", test)
            status.success?
          end
        end

        # Test files that name a moved file's stem or a constant it defines,
        # most mentions first.
        def related_tests(plan)
          needles = needles_for(plan)
          return [] if needles.empty?

          hits = test_files.to_h { |file| [file, needles.count { |needle| File.read(file).include?(needle) }] }
          hits.select { |_file, count| count.positive? }.sort_by { |_file, count| -count }
              .first(TEST_CAP).map { |file, _count| file.delete_prefix("#{@master}/") }
        end

        def test_files = Dir.glob(File.join(@master, "test", "**", "*.rb"))
        def needles_for(plan) = plan.paths.flat_map { |path| names_in(path, plan.writes[path]) }.uniq

        def names_in(path, new_text)
          stem = File.basename(path, ".*")
          old = File.join(repo_root, path)
          text = [new_text, File.file?(old) ? File.read(old) : nil].compact.join("\n")
          constants = text.scan(/^\s*(?:class|module)\s+([A-Z]\w+)/).flatten - Restructure.namespaces(@master)
          [stem.length >= 4 ? stem : nil, *constants].compact
        end

        def run(*command)
          Master::Io::Exec.capture2e(ENV_BOOT, Master::BUNDLE_BIN, "exec", *command, chdir: @master, timeout: TIMEOUT_S)
        end

        def repo_root = File.dirname(@master)
      end
    end
  end
end
