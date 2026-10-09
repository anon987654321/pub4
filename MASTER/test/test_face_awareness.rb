# frozen_string_literal: true

require_relative "test_helper"

# The face attends through one contract (laws.yml spatial.awareness). The
# browser reads it as MASTER_FACE_CONTRACT; the terminal through Face::Contract.
class TestFaceAwareness < Minitest::Test
  C = Master::Face::Contract

  def test_the_contract_declares_listening_speaking_and_the_echo_gate
    spec = C.awareness
    assert_operator spec.dig("listening", "glance_scale"), :<, 1.0
    assert_operator spec.fetch("heard_hold_ms"), :>, 0
    assert_operator spec.dig("echo_safe", "tts_tail_ms"), :>, 0
  end

  def test_the_mic_is_not_trusted_while_master_is_audible_or_just_finished
    refute C.echo_safe?(playing: true)
    refute C.echo_safe?(playing: false, loading: true)
    refute C.echo_safe?(playing: false, ms_since_tts_end: 100)
    assert C.echo_safe?(playing: false, ms_since_tts_end: 5_000)
    assert C.echo_safe?(playing: false)
  end

  def test_listening_narrows_glances_and_leans_in_further_while_the_user_speaks
    spread = lambda do |state|
      motion = Master::CLI::Face::Motion.new(seed: 3)
      reach = 0.0
      600.times do |i|
        look = motion.step(state:, t: i * 0.05)
        reach = [reach, look.gaze_lon.abs].max if look.respond_to?(:gaze_lon)
      end
      [motion, reach]
    end
    _m, idle = spread.call(:idle)
    _m, listening = spread.call(:listening)
    assert_operator listening, :<=, idle if idle.positive?
  end

  def test_the_browser_feeds_awareness_only_through_the_echo_gate
    part3 = File.read(File.join(Master::ROOT, "..", "RAILS", "master_web", "public", "face.part3.txt"))
    part5 = File.read(File.join(Master::ROOT, "..", "RAILS", "master_web", "public", "face.part5.txt"))
    assert_includes part3, "function faceEchoSafe"
    assert_includes part5, "if (faceEchoSafe()) State.heardAt"
    refute_match(/State\.heardAt\s*=(?!.*faceEchoSafe)/, part5.lines.reject { |l| l.include?("faceEchoSafe") }.join)
  end
end
