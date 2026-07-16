# frozen_string_literal: true

require "minitest/autorun"

class SharedWiringGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_shared_wiring_gate_lib_exists
    path = File.join(ROOT, "gates/lib/shared_wiring_gate.rb")
    assert File.file?(path)
  end

  def test_release_gate_calls_domain_alignment_in_process
    source = File.read(File.join(ROOT, "release_gate.rb"))
    assert_includes source, "Deploy::DomainAlignmentGate"
    assert_includes source, "gate.run"
    refute_includes source, '"domain_alignment_gate.rb"'
  end

  def test_runner_registers_shared_wiring_gate
    source = File.read(File.join(ROOT, "gates/runner.rb"))
    assert_includes source, "shared_wiring:"
    assert_includes source, "gates/shared_wiring_gate.rb"
  end
end