# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/deploy_stamp"

class TestDeployStamp < Minitest::Test
  def with_stamp(body)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "last_deploy_master.json"), body) if body
      yield dir
    end
  end

  def test_the_stamp_sha_is_read_and_a_missing_or_torn_stamp_is_nil
    with_stamp(%({"app":"master","sha":"aa4f010c1","status":"ok"})) do |dir|
      assert_equal "aa4f010c1", Deploy::DeployStamp.sha("master", dir:)
    end
    with_stamp(nil) { |dir| assert_nil Deploy::DeployStamp.sha("master", dir:) }
    with_stamp(%({"app":"mas)) { |dir| assert_nil Deploy::DeployStamp.sha("master", dir:) }
  end

  # Measured on vm23 2026-09-15: /health said aa4f010c1 and the stamp said
  # aa4f010c1, while the checkout had moved on to b9d0f4fac.
  def test_the_booted_build_matching_the_stamp_passes_at_either_short_length
    assert_nil Deploy::DeployStamp.booted_mismatch(app: "master", booted: "aa4f010c1", stamped: "aa4f010c1")
    assert_nil Deploy::DeployStamp.booted_mismatch(app: "master", booted: "aa4f010c1e", stamped: "aa4f010c1")
  end

  def test_a_build_no_deploy_ran_fails_and_names_both_commits
    line = Deploy::DeployStamp.booted_mismatch(app: "master", booted: "b9d0f4fac", stamped: "aa4f010c1")

    assert_includes line, "b9d0f4fac"
    assert_includes line, "aa4f010c1"
  end

  def test_a_process_that_cannot_name_its_build_fails
    refute_nil Deploy::DeployStamp.booted_mismatch(app: "master", booted: nil, stamped: "aa4f010c1")
  end

  def test_no_stamp_is_not_a_mismatch
    assert_nil Deploy::DeployStamp.booted_mismatch(app: "master", booted: "aa4f010c1", stamped: nil)
  end
end
