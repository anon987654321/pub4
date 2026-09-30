# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../lib/master"

class ControlPlaneSpec < Minitest::Test
  Status = Struct.new(:success?)

  def test_dirty_checkout_waits_before_fetching
    Dir.mktmpdir("master-control") do |root|
      runner = []
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      plane.define_singleton_method(:command) do |*argv|
        runner << argv
        { stdout: " M changed\n", stderr: "", status: Status.new(false) }
      end

      plane.cycle

      assert_equal [["git", "-C", File.expand_path("..", root), "status", "--porcelain"]], runner
    end
  end

  def test_cycle_rejects_a_non_main_checkout
    Dir.mktmpdir("master-control") do |root|
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      calls = 0
      plane.define_singleton_method(:command) do |*argv|
        calls += 1
        if argv[-2, 2] == ["status", "--porcelain"]
          { stdout: "", stderr: "", status: Status.new(true) }
        else
          { stdout: "develop\n", stderr: "", status: Status.new(true) }
        end
      end

      plane.cycle

      assert_equal 2, calls
    end
  end

  def test_process_lock_is_the_single_master_mutex
    dir = Dir.mktmpdir("master-lock")
    path = File.join(dir, "master.lock")
    first = Master::Ops::ProcessLock.acquire!(path:, mode: "test")
    refute_nil first
    begin
      reader, writer = IO.pipe
      child = fork do
        reader.close
        second = Master::Ops::ProcessLock.acquire!(path:, mode: "child")
        writer.write(second ? "locked\n" : "blocked\n")
        writer.close
        Master::Ops::ProcessLock.release(second)
        exit(second ? 1 : 0)
      end
      writer.close
      assert_equal "blocked\n", reader.read
      Process.wait(child)
      assert_equal 0, $CHILD_STATUS.exitstatus
    ensure
      reader&.close
      writer&.close
      Master::Ops::ProcessLock.release(first)
      FileUtils.remove_entry(dir)
    end
  end
end
