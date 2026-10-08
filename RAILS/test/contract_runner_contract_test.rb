# frozen_string_literal: true

require "minitest/autorun"

class ContractRunnerContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source
    @source ||= File.read(File.join(ROOT, "test", "run_all.rb"))
  end

  def test_contract_runner_isolated_per_file
    assert_includes source, "Open3.popen2e"
    assert_includes source, "pgroup: true"
    assert_includes source, "Timeout.timeout"
  end

  def test_contract_runner_can_replay_passing_files_with_deterministic_seeds
    assert_includes source, 'REPLAY = Integer(ENV.fetch("CONTRACT_REPLAY", "0"))'
    assert_includes source, "Digest::SHA256.hexdigest"
    assert_includes source, %(["--seed", seed.to_s])
    assert_includes source, ":flake"
  end

  def test_flake_is_not_a_pass
    assert_includes source, "outcome.status == :pass && REPLAY.positive?"
    assert_includes source, "outcome.status != :pass"
  end
end
