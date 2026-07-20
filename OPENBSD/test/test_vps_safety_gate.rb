# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class VpsSafetyGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_gate_passes_on_repo_fixture_paths
    gate = File.join(ROOT, "vps_safety_gate.rb")
    skip "gate missing" unless File.file?(gate)

    out, status = Open3.capture2e(RbConfig.ruby, gate)
    assert status.success?, "expected VPS safety gate to pass, got:\n#{out}"
    assert_includes out, "VPS safety gate passed"
  end

  def test_console_scripts_live_at_openbsd_top_level
    %w[validate_doas.ksh vps_console_common.exp vps_drop_install.exp].each do |name|
      assert File.file?(File.join(ROOT, name)), "missing #{name} at OPENBSD top level"
    end
  end
end
