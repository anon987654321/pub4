# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pid_probe"

class PidProbeTest < Minitest::Test
  def test_live_pid_is_reported_alive
    assert Deploy::PidProbe.alive?(Process.pid)
  end

  def test_malformed_pid_is_rejected_without_a_process_probe
    [nil, "", "garbage", "0", 0, -1, "12x", " 123"].each do |pid|
      with_kill(->(*) { flunk "must not probe malformed PID #{pid.inspect}" }) do
        refute Deploy::PidProbe.alive?(pid), "expected #{pid.inspect} to be stale"
      end
    end
  end

  def test_missing_process_is_stale
    with_kill(->(*) { raise Errno::ESRCH }) do
      refute Deploy::PidProbe.alive?("12345")
    end
  end

  def test_permission_denied_means_process_exists
    with_kill(->(*) { raise Errno::EPERM }) do
      assert Deploy::PidProbe.alive?("12345")
    end
  end

  private

  # minitest 6 no longer ships minitest/mock, and OPENBSD's tests run on the
  # system minitest, so Process.kill is swapped the way test_dns_facts_agree does.
  def with_kill(fake)
    original = Process.method(:kill)

    Process.define_singleton_method(:kill, &fake)
    yield
  ensure
    Process.define_singleton_method(:kill, original)
  end
end
