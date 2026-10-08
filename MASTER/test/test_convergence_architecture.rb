# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/convergence/architecture"

class TestConvergenceArchitecture < Minitest::Test
  def test_explanation_names_the_real_four_tree_boundary
    text = Master::Convergence::Architecture.render(root: Master::REPO_ROOT)
    assert_includes text, "MASTER / RAILS / OPENBSD / STUDIO"
    assert_includes text, "architecture: MASTER"
  end

  def test_unknown_target_is_explicit
    assert_includes Master::Convergence::Architecture.render(target: "wat"), "unknown tree"
  end
end
