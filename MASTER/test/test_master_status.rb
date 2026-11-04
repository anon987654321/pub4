# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "tmpdir"

# `bin/master --status` names the control plane's holder without taking it.
class TestMasterStatus < Minitest::Test
  BIN = File.expand_path("../bin/master", __dir__)

  def status_line(lock)
    out, = Open3.capture2e({ "MASTER_PROCESS_LOCK_PATH" => lock }, RbConfig.ruby, BIN, "--status")
    out.lines.grep(/master0:/).last.to_s
  end

  def test_it_reports_a_free_control_plane
    Dir.mktmpdir { |dir| assert_includes status_line(File.join(dir, "process.lock")), "control plane free" }
  end

  def test_it_names_the_holder_and_leaves_the_lock_held
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "process.lock")
      held = Master::Ops::ProcessLock.acquire!(path: lock, mode: "interactive")

      line = status_line(lock)

      assert_match(/held by pid=#{Process.pid} mode=interactive/, line)
      assert_nil Master::Ops::ProcessLock.acquire!(path: lock, mode: "probe"), "--status must not take the lock"
    ensure
      Master::Ops::ProcessLock.release(held) if held
    end
  end
end
