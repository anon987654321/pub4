# frozen_string_literal: true

require_relative "test_helper"

class TestPairing < Minitest::Test
  def setup
    @root = Dir.mktmpdir("master-pair-")
    Fiber[:master_paired] = nil
    Fiber[:master_pair_subject] = nil
    Fiber[:master_visitor] = nil
    Fiber[:master_elevated] = nil
  end

  def teardown
    FileUtils.rm_rf(@root)
    Fiber[:master_paired] = nil
    Fiber[:master_pair_subject] = nil
    Fiber[:master_visitor] = nil
    Fiber[:master_elevated] = nil
  end

  def test_issue_and_redeem_grants_a_token
    issued = Master::Ground::Pairing.issue(root: @root, label: "phone")
    assert_match(/\A[A-Z2-9]{8}\z/, issued[:code])
    assert_equal 600, issued[:expires_in]

    result = Master::Ground::Pairing.redeem(issued[:code], root: @root)
    refute_nil result
    assert Master::Ground::Pairing.valid_token?(result[:token], root: @root)
    assert_equal result[:subject], Master::Ground::Pairing.subject_for(result[:token], root: @root)
    assert File.file?(File.join(@root, ".master", "workspace", result[:subject], "USER.md"))
  end

  def test_code_is_single_use_and_case_insensitive
    issued = Master::Ground::Pairing.issue(root: @root)
    assert Master::Ground::Pairing.redeem(issued[:code].downcase, root: @root)
    assert_nil Master::Ground::Pairing.redeem(issued[:code], root: @root)
  end

  def test_expired_code_is_rejected
    issued = Master::Ground::Pairing.issue(root: @root)
    path = Master::Ground::Pairing.codes_path(@root)
    codes = Master::Ground::Pairing.load_yaml(path)
    codes[issued[:code]]["expires_at"] = Time.now.to_i - 1
    Master::Ground::Pairing.persist(path, codes)

    assert_nil Master::Ground::Pairing.redeem(issued[:code], root: @root)
  end

  def test_revoke_drops_the_token
    issued = Master::Ground::Pairing.issue(root: @root)
    result = Master::Ground::Pairing.redeem(issued[:code], root: @root)
    assert Master::Ground::Pairing.revoke(result[:token], root: @root)
    refute Master::Ground::Pairing.valid_token?(result[:token], root: @root)
  end

  def test_apply_remote_forces_visitor_until_paired
    Fiber[:master_visitor] = nil
    Master::Ground::Pairing.apply_remote!(:irc)
    assert_equal true, Fiber[:master_visitor]

    Fiber[:master_visitor] = nil
    Fiber[:master_paired] = true
    Master::Ground::Pairing.apply_remote!(:irc)
    assert_nil Fiber[:master_visitor]
  end

  def test_apply_remote_leaves_cli_and_web_alone
    Fiber[:master_visitor] = nil
    Master::Ground::Pairing.apply_remote!(:web)
    Master::Ground::Pairing.apply_remote!(:cli)
    assert_nil Fiber[:master_visitor]
  end

  def test_required_for_remote_reads_the_file
    assert Master::Ground::Pairing.required_for_remote_channels?
    assert Master::Ground::Pairing.required_for_remote?(:matrix)
    refute Master::Ground::Pairing.required_for_remote?(:web)
  end
end
