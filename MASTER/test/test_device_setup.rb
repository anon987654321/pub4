# frozen_string_literal: true

require_relative "test_helper"

# A new Termux install sets up the face's ear by itself. Every command here is
# stubbed: a test never runs pkg, git, cmake or curl.
class TestDeviceSetup < Minitest::Test
  Setup = Master::Device::Setup

  def setup
    @dir = Dir.mktmpdir
    @state = File.join(@dir, "face_setup.json")
    @ran = []
    @present = []
    @now = 1_000_000
    @out = StringIO.new
  end

  def teardown = FileUtils.rm_rf(@dir)

  # installs: which argv puts which command on PATH when it succeeds.
  def setup_with(fails: [], installs: {})
    Setup.new(env: { "PREFIX" => "/data/data/com.termux/files/usr" }, which: ->(cmd) { @present.include?(cmd) },
              clock: -> { @now }, state_path: @state, out: @out,
              sh: lambda { |argv|
                @ran << argv
                next false if fails.any? { |word| argv.include?(word) }

                @present.concat(Array(installs[argv.first(4)]))
                true
              })
  end

  def test_the_plan_names_the_packages_the_build_and_the_model
    steps = setup_with.plan
    assert_equal %i[packages whisper model], steps.map(&:name)
    assert_equal [%w[pkg install -y termux-api sox ffmpeg pulseaudio]], steps[0].tries.first
    pkg_try, build = steps[1].tries
    assert_equal [%w[pkg install -y x11-repo], %w[pkg install -y whisper-cpp]], pkg_try
    assert_equal %w[pkg install -y git cmake clang make curl], build[0]
    assert_includes build.map(&:first), "cmake"
    assert_equal "/data/data/com.termux/files/usr/bin/whisper-cli", build.last.last
    assert_equal "curl", steps[2].tries.first[1].first
    assert steps[2].tries.first[1].last.end_with?("ggml-base.bin")
  end

  def test_nothing_runs_when_the_ear_is_in_place
    @present.concat(%w[termux-speech-to-text sox ffmpeg parec whisper-cli])
    setup = setup_with
    model = File.join(@dir, "ggml-base.bin")
    File.open(model, "wb") { |f| f.truncate(Master::CLI::Face::Transcriber::MIN_MODEL_BYTES) }
    setup.define_singleton_method(:model_path) { model }
    setup.run
    assert_empty @ran
    assert_equal "done", JSON.parse(File.read(@state)).dig("whisper", "state")
  end

  def test_whisper_builds_from_source_when_pkg_lacks_it
    @present.concat(%w[termux-speech-to-text sox ffmpeg parec])
    setup = setup_with(fails: ["whisper-cpp"], installs: { ["install", "-m", "755", File.join(Setup::SOURCE, "build", "bin", "whisper-cli")] => "whisper-cli" })
    setup.define_singleton_method(:plan) { super().select { |step| step.name == :whisper } }
    setup.run
    assert_equal %w[pkg install -y whisper-cpp], @ran[1]
    assert_equal "install", @ran.last.first
    assert_match(/ear0: whisper ready/, @out.string)
  end

  def test_a_finished_step_is_not_repeated_on_the_next_boot
    installs = { %w[pkg install -y termux-api] => %w[termux-speech-to-text sox ffmpeg parec] }
    setup = setup_with(installs:)
    setup.define_singleton_method(:plan) { super().first(1) }
    setup.run
    assert_equal 1, @ran.size
    setup.run
    assert_equal 1, @ran.size, "the next boot ran pkg again"
  end

  def test_a_failed_build_waits_and_backs_off
    setup = setup_with(fails: %w[whisper-cpp cmake])
    setup.define_singleton_method(:plan) { super().select { |step| step.name == :whisper } }
    setup.run
    tries = @ran.size
    entry = JSON.parse(File.read(@state))["whisper"]
    assert_equal 1, entry["failures"]
    assert_equal @now + 3_600, entry["retry_at"]

    setup.run
    assert_equal tries, @ran.size, "a failed build retried at once"
    assert_match(/whisper waits until/, @out.string)

    @now += 3_600
    setup.run
    assert_equal @now + 7_200, JSON.parse(File.read(@state)).dig("whisper", "retry_at"), "the wait did not double"
  end

  def test_the_build_stops_after_five_failures
    setup = setup_with(fails: %w[whisper-cpp cmake])
    setup.define_singleton_method(:plan) { super().select { |step| step.name == :whisper } }
    File.write(@state, JSON.generate("whisper" => { "state" => "failed", "failures" => 5, "retry_at" => 0 }))
    setup.run
    assert_empty @ran
    assert_match(/stopped after 5 failures/, @out.string)
  end

  def test_it_never_starts_under_test_or_off_a_phone
    phone = Struct.new(:android?).new(true)
    assert_nil Setup.start!(device: phone, env: { "MASTER_IN_PROOF" => "1" })
    assert_nil Setup.start!(device: phone, env: { "MASTER_FACE_SETUP" => "0" })
    assert_nil Setup.start!(device: Struct.new(:android?).new(false), env: {})
  end
end
