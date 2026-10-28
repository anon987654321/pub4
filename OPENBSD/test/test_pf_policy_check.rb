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
    assert_includes result.failures.join("\n"), "contains unscoped"
  end

  def test_unfinished_final_continuation_is_rejected
    source = File.read(File.join(FIXTURES, "good.conf")) + "pass in on $ext_if \\\n"
    result = check_content(source)
    assert_includes result.failures.join("\n"), "unfinished PF continuation"
  end

  def test_symlinked_pf_config_is_rejected
    Dir.mktmpdir("pf-policy-symlink") do |root|
      path = File.join(root, "OPENBSD", "etc", "pf.conf")
      target = File.join(root, "external-pf.conf")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(target, File.read(File.join(ROOT, "OPENBSD", "etc", "pf.conf")))
      File.symlink(target, path)

      result = Deploy::PfPolicyCheck.run(root:)
      assert_includes result.failures.join("\n"), "refuses symlinked"
    end
  end

  def test_symlinked_pf_parent_directory_is_rejected
    Dir.mktmpdir("pf-policy-parent-symlink") do |root|
      shared = File.join(root, "OPENBSD")
      outside = File.join(root, "external-openbsd")
      FileUtils.mkdir_p(File.join(shared, "etc"))
      FileUtils.mkdir_p(File.join(outside, "etc"))
      FileUtils.cp(File.join(ROOT, "OPENBSD", "etc", "pf.conf"),
                   File.join(outside, "etc", "pf.conf"))
      FileUtils.rm_rf(shared)
      File.symlink(outside, shared)

      result = Deploy::PfPolicyCheck.run(root:)
      assert_includes result.failures.join("\n"), "parent path is not a real directory"
    end
  end

  def test_invalid_utf8_pf_config_is_rejected
    Dir.mktmpdir("pf-policy-invalid-utf8") do |root|
      path = File.join(root, "OPENBSD", "etc", "pf.conf")
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, [0xFF].pack("C"))

      result = Deploy::PfPolicyCheck.run(root:)
      assert_includes result.failures.join("\n"), "invalid UTF-8"
    end
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
    check_content(File.read(File.join(FIXTURES, name)))
  end

  def check_content(source)
    Dir.mktmpdir("pf-policy-test") do |dir|
      target = File.join(dir, "OPENBSD", "etc", "pf.conf")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, source)
      return Deploy::PfPolicyCheck.run(root: dir)
    end
  end
end
