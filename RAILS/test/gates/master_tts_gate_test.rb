# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "gate_probe_harness"
require_relative "../../../MASTER/gates/master_tts"

# master_tts moved to MASTER/gates on 2026-09-11 and kept its row in
# RAILS/gates/gates.yml, so it is reached through `require_gate`, which resolves a
# path naming a tree from the repo root. That is the first thing worth pinning:
# the gate that broke on this move broke on path arithmetic, not on its checks.
#
# What the gate itself does is read seven files and look for strings. Every one of
# them is a wiring fact that fails silently — the espeak fallback, the bundle
# isolation that keeps the worker out of the web app's Gemfile, the 45-second
# timeout in rc.d. So the gate is honest about its reach only if the reader knows
# it read source: it can say the fallback is wired and cannot say a voice came
# out. The last test holds that line.
class MasterTtsGateTest < Minitest::Test
  include GateProbe

  GATE = Deploy::MasterTtsGate

  # A tree that satisfies every declared check, built from the gate's own CHECKS
  # table rather than from a second copy of it: a needle added to the gate must
  # not need a matching edit here, or the fixture becomes the thing under test.
  def plant(root, omit: nil)
    GATE::CHECKS.each do |relative, needles|
      path = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, needles.reject { |n| n == omit }.join("\n"))
    end
    worker = File.join(root, "MASTER", "bin", "tts-worker")
    FileUtils.chmod(0o755, worker)
  end

  def run_against(root)
    with_const(GATE, :ROOT, root) do
      with_const(GATE, :MASTER, File.join(root, "MASTER")) { GATE.run }
    end
  end

  def with_tree(omit: nil)
    Dir.mktmpdir("master-tts") do |root|
      plant(root, omit: omit)
      yield root
    end
  end

  def test_a_missing_needle_is_named_with_the_file_that_lost_it
    with_tree(omit: "def espeak_path") do |root|
      result = run_against(root)

      assert_equal :failed, result.outcome
      assert_match(%r{MASTER/lib/voice/speech\.rb missing "def espeak_path"}, result.failures.join(" | "))
    end
  end

  def test_a_tree_with_every_needle_present_passes
    with_tree do |root|
      result = run_against(root)

      assert_equal :passed, result.outcome, result.failures.join(" | ")
      assert_operator result.checks_ran, :>, GATE::CHECKS.values.sum(&:size)
    end
  end

  # The worker is started by rc.d as the master user. A file that lost its mode
  # bit fails at boot with nothing in the gate's own checks to explain it.
  def test_a_worker_that_is_not_executable_is_named
    with_tree do |root|
      FileUtils.chmod(0o644, File.join(root, "MASTER", "bin", "tts-worker"))

      assert_match(/tts-worker must be executable/, run_against(root).failures.join(" | "))
    end
  end

  def test_a_missing_file_is_named_once_rather_than_once_per_needle
    with_tree do |root|
      FileUtils.rm(File.join(root, "OPENBSD", "etc", "rc.d", "master"))
      failures = run_against(root).failures

      assert_equal ["missing OPENBSD/etc/rc.d/master"], failures.grep(%r{rc\.d/master})
    end
  end

  # MASTER_TTS_REQUIRE_HOST_BACKEND is the gate's only claim about the machine it
  # runs on, and it is a hard failure rather than a missing precondition. That is
  # right on the deploy host and is why it is opt-in: a Mac with neither binary is
  # not a broken fleet, so the flag has to be asked for.
  def test_the_host_backend_check_is_opt_in_and_fails_rather_than_skipping
    with_tree do |root|
      clean = run_against(root)

      assert_equal :passed, clean.outcome

      ENV["MASTER_TTS_REQUIRE_HOST_BACKEND"] = "1"
      strict = run_against(root)
      skip "this machine has edge-tts or espeak installed" if strict.ok?

      assert_match(/host missing edge-tts\/espeak backend/, strict.failures.join(" | "))
    ensure
      ENV.delete("MASTER_TTS_REQUIRE_HOST_BACKEND")
    end
  end

  # The pass line is "MASTER TTS gate passed." and every check behind it is a
  # string in a file. Nothing here starts the worker, opens its socket or asks for
  # a sample, so a green master_tts means the wiring is declared — not that TTS
  # speaks. Pinned so the claim cannot quietly widen.
  def test_every_check_reads_source_so_the_pass_line_cannot_mean_tts_works
    source = File.read(File.join(GATE::ROOT, "MASTER", "gates", "master_tts.rb"))

    refute_match(/Net::HTTP|TCPSocket|UNIXSocket|Open3/, source,
                 "a gate that speaks to the daemon needs a third state for the daemon being down")
    assert_match(/File\.read\(path\)/, source)
  end
end
