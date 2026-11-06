# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"
require "tmpdir"
require_relative "../lib/fix/server_leases"

# The servers a /fix run booted outlived it by hours when it was stopped: bin/master's traps end in
# exit!, and nothing reaped what a dead run left.
class TestServerLeases < Minitest::Test
  Leases = Master::Fix::ServerLeases

  def lease(run_dir, name, owner:, pid:)
    File.write(File.join(run_dir, "#{name}.pid"), "#{pid}\n")
    File.write(File.join(run_dir, "#{name}.pid.owner"), "#{owner} #{pid}\n")
  end

  def test_the_server_of_a_dead_owner_is_reaped
    Dir.mktmpdir("triangle-run") do |run_dir|
      lease(run_dir, "amber", owner: 111, pid: 61_352)
      killed = []

      reaped = Leases.reap_orphans!(run_dir, alive: ->(_owner) { false }, killer: ->(pid) { killed << pid })

      assert_equal ["amber"], reaped
      assert_equal [61_352], killed
      refute File.exist?(File.join(run_dir, "amber.pid"))
    end
  end

  def test_a_live_owners_server_and_a_stale_lease_are_not_killed
    Dir.mktmpdir("triangle-run") do |run_dir|
      lease(run_dir, "master", owner: 222, pid: 53_187)
      lease(run_dir, "bsdports", owner: 333, pid: 47_312)
      File.delete(File.join(run_dir, "bsdports.pid"))
      killed = []

      reaped = Leases.reap_orphans!(run_dir, alive: ->(owner) { owner == 222 }, killer: ->(pid) { killed << pid })

      assert_empty reaped
      assert_empty killed
      assert File.exist?(File.join(run_dir, "master.pid.owner")), "a live run's server is its own"
      refute File.exist?(File.join(run_dir, "bsdports.pid.owner")), "a stale lease is only removed"
    end
  end

  # The real trap context, where a Mutex cannot be taken and exit! follows at once.
  def test_a_term_trap_that_exits_bang_still_stops_the_held_server
    Dir.mktmpdir("trap-proof") do |dir|
      marker = File.join(dir, "stopped")
      status = term_child(trap_script(dir, marker))

      assert_equal 143, status.exitstatus
      assert_equal "61352", File.read(marker)
    end
  end

  def term_child(script)
    IO.popen([RbConfig.ruby, "-e", script], err: File::NULL) do |child|
      assert_equal "ready\n", child.gets

      Process.kill("TERM", child.pid)
      Process.wait2(child.pid).last
    end
  end

  def trap_script(dir, marker)
    <<~RUBY
      require #{File.expand_path("../lib/fix/server_leases", __dir__).inspect}

      lease = Object.new
      lease.define_singleton_method(:stop_owned!) { File.write(#{marker.inspect}, "61352") }
      Master::Fix::ServerLeases.hold(lease, pid_path: #{File.join(dir, "amber.pid").inspect}, pid: 61_352)
      trap("TERM") { Master::Fix::ServerLeases.stop_all_from_trap!; exit!(143) }
      $stdout.puts "ready"
      $stdout.flush
      sleep 30
    RUBY
  end
end
