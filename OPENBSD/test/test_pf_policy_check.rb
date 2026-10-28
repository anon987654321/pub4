# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../checks/pf_policy_check"

class PfPolicyCheckTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  FIXTURES = File.join(__dir__, "fixtures", "pf_policy")

  def test_tracked_pf_configuration_passes
    result = Deploy::PfPolicyCheck.run(root: ROOT)
    assert result.ok?, result.failures.join("\n")
  end

  def test_good_fixture_passes
    result = check_fixture("good.conf")
    assert result.ok?, result.failures.join("\n")
  end

  def test_default_deny_is_required_before_pass_rules
    result = check_fixture("late_default_deny.conf")
    assert_includes result.failures.join("\n"), "default-deny block appears after the first pass rule"
  end

  def test_unscoped_pass_is_rejected
    result = check_fixture("unscoped_pass.conf")
    assert_includes result.failures.join("\n"), "contains unscoped"
  end

  def test_unscoped_protocol_pass_is_rejected
    result = check_fixture("unscoped_protocol_pass.conf")
    assert_includes result.failures.join("\\n"), "contains unscoped"
  end

  def test_bruteforce_block_must_precede_other_inbound_passes
    result = check_fixture("late_bruteforce_block.conf")
    assert_includes result.failures.join("\n"), "precedes the <bruteforce> quick block"
  end

  def test_bruteforce_block_is_required
    result = check_fixture("missing_bruteforce_block.conf")
    assert_includes result.failures.join("\n"), "quick block for <bruteforce> is missing"
  end

  private

  def check_fixture(name)
    Dir.mktmpdir("pf-policy-test") do |dir|
      target = File.join(dir, "OPENBSD", "etc", "pf.conf")
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.join(FIXTURES, name), target)
      return Deploy::PfPolicyCheck.run(root: dir)
    end
  end
end
