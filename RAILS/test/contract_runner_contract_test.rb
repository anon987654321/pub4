# frozen_string_literal: true

require "minitest/autorun"

class ContractRunnerContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source
    @source ||= File.read(File.join(ROOT, "test", "run_all.rb"))
  end

  def test_contract_runner_isolated_per_file_uses_shared_bounded_capture
    assert_includes source, "Shared::Subprocess.capture2e"
    assert_includes source, "timeout: TIMEOUT"
    refute_includes source, "Open3.popen2e"
    refute_includes source, "Timeout.timeout"
    refute_includes source, "def kill_group"
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
