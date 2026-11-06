# frozen_string_literal: true

require "minitest/autorun"

# bin/ci ran one node file, face_boot.test.mjs, while two dozen others sat
# beside it and never ran; a node test bin/ci does not run guards nothing.
class CiContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_bin_ci_runs_every_node_test
    steps = File.read(File.join(ROOT, "config", "ci.rb")).scan(/node --test ([^"]+)"/).flatten
    covered = steps.flat_map { |pattern| Dir.glob(pattern.split, base: ROOT) }
    node_tests = Dir.glob("test/**/*.test.mjs", base: ROOT)

    refute_empty node_tests
    assert_empty node_tests - covered, "node tests bin/ci never runs"
  end
end
