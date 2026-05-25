# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require_relative "../../lib/master"
require_relative "../../lib/ops/loop_owner"

class LoopOwnerSpec < Minitest::Test
  def setup
    Master::Ops::LoopOwner.release
  end

  def teardown
    Master::Ops::LoopOwner.release
  end

  def test_claim_records_active_loop
    assert Master::Ops::LoopOwner.claim("watcher")
    active = Master::Ops::LoopOwner.active
    assert_equal "watcher", active["loop"]
    assert active["pid"]
  end

  def test_second_claim_fails_until_release
    assert Master::Ops::LoopOwner.claim("watcher")
    refute Master::Ops::LoopOwner.claim("autofix")
    Master::Ops::LoopOwner.release
    assert Master::Ops::LoopOwner.claim("autofix")
  end

  def test_with_claim_releases_after_block
    result = Master::Ops::LoopOwner.with_claim("watcher") { :ok }
    assert_equal :ok, result
    assert_nil Master::Ops::LoopOwner.active
  end
end
