# frozen_string_literal: true

module Master
  module Fix
    class Restructure
      # MASTER still eager-loads, which proves Zeitwerk naming; the separate
      # self-test command checks the constitutional ceilings around it.
      class MasterProof < Proof
        ENV_BOOT = { "MASTER_FAST" => "1" }.freeze

        private

        def tree_baseline(_plan) = breaches

        def tree_failure(_plan, before)
          load_failure || breach_failure(before)
        end

        def load_failure
          out, status = run(RbConfig.ruby, "-Ilib", "-e", 'require "master"; Master.eager_load!')
          "MASTER no longer eager-loads: #{out.lines.last(3).join.strip[0, 400]}" unless status.success?
        end

        def breach_failure(before)
          added = breaches - Array(before)
          "self-test ceiling breached: #{added.first(3).join("; ")}" unless added.empty?
        end

        def breaches
          out, = run("rake", "selftest")
          out.lines.grep(/\(max \d+\)/).map { |line| line.strip.sub(%r{\A.*?/MASTER/}, "") }
        end

        def test_files(_plan) = Dir.glob(File.join(@tree_root, "test", "**", "*.rb"))
        def run_test(test) = run(RbConfig.ruby, "-Ilib", "-Itest", test)

        def run(*command)
          Master::Io::Exec.capture2e(ENV_BOOT, Master::BUNDLE_BIN, "exec", *command, chdir: @tree_root,
                                                                                   timeout: TIMEOUT_S)
        end
      end
    end
  end
end
