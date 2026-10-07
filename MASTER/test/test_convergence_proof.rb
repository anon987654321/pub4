# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/convergence/proof"

class TestConvergenceProof < Minitest::Test
  def test_local_proof_reaches_a_truthful_state
    result = Master::Convergence::Proof.run(root: Master::REPO_ROOT)
    assert_includes %i[pass inconclusive], result[:state]
    assert_operator result[:checks].size, :>=, 5
    assert File.file?(result[:receipt][:path])
  end
end
