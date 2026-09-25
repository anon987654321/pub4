# frozen_string_literal: true

module Master
  module Fix
    class Restructure
      # OPENBSD and MASTER/tools have no loader to ask, so the proof is what parses
      # and what the tree's own tests say. Their test files run one process
      # each, as run_all.rb and MASTER/tools's Rakefile run them, because each tool
      # defines its constants at top level and the names collide.
      class ScriptProof < Proof
        private

        def test_files(_plan) = Dir.glob(File.join(@tree_root, "test", "**", "test_*.rb"))

        def run_test(test)
          run = -> { Master::Io::Exec.capture2e(RbConfig.ruby, "-Itest", test, chdir: @tree_root, timeout: TIMEOUT_S) }
          defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
        end
      end
    end
  end
end
