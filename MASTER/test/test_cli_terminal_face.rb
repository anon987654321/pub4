# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face"
require_relative "../lib/cli/face/window"

class TestCliTerminalFace < Minitest::Test
  Quiet = Struct.new(:missing) do
    def available? = missing.nil?
  end

  BRAILLE = /[⠁-⣿]/

  def window
    Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear: Quiet.new(nil),
      mouth: Quiet.new(nil),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [30, 60] }
    )
  end

  def rows_of(screen)
    screen.scan(/\e\[(\d+);1H(.*?)\e\[K/).to_h do |row, text|
      [row.to_i, text.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")]
    end
  end

  def test_the_face_owns_the_stage_and_control_strip
    painted = rows_of(window.screen(30, 80, 2.0)).values
    assert painted.any? { |text| text.match?(BRAILLE) }
    assert painted.any? { |text| text.include?("idle, mic on") }
    refute painted.any? { |text| text.include?("/ FACE") }
    refute painted.any? { |text| text.include?("recent") }
  end

  def test_every_row_of_the_window_is_painted
    assert_equal (1..30).to_a, rows_of(window.screen(30, 80, 2.0)).keys.sort
  end

  def test_the_renderer_receives_the_controlled_height_and_full_width
    seen = nil
    renderer = ->(**kwargs) do
      seen = [kwargs.fetch(:rows), kwargs.fetch(:cols)]
      Array.new(seen.first, " " * seen.last).join("\n")
    end
    Master::CLI::Face.stub(:frame, renderer) { window.screen(30, 80, 2.0) }
    assert_equal 23, seen.first
    assert_equal 80, seen.last
  end

  def test_motion_has_a_camera_dolly
    motion = Master::CLI::Face::Motion.new(seed: 7)
    motion.step(state: :idle, t: 1.0)
    thinking = motion.step(state: :thinking, t: 2.0).dolly
    assert_operator thinking, :>, 0.95
  end

  def test_motion_keeps_the_face_readable
    motion = Master::CLI::Face::Motion.new(seed: 7)
    120.times do |i|
      look = motion.step(state: :idle, t: (i + 1) / 15.0)
      assert_operator look.yaw.abs, :<=, 0.5
      assert_operator look.dolly, :between?, 0.95, 1.10
    end
  end

  def test_the_control_strip_keeps_the_latest_transcript
    face = window
    5.times { |i| face.send(:note_job, ["job #{i}"]) }
    text = rows_of(face.screen(30, 80, 2.0)).values.join("\n")
    assert_includes text, "job 4"
    assert_includes text, "job 2"
    refute_includes text, "job 0"
  end

  def test_typed_input_uses_the_user_token
    assert_equal "$ hello", window.send(:typed, "hello", 80)
  end

  def test_a_failed_turn_does_not_start_picture_work
    face = Master::CLI::Face::Window.new(
      turn: ->(_) { Master::Result.err("talk0: empty response", category: :provider_error) },
      ear: Quiet.new(false),
      mouth: Quiet.new(false),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] }
    )
    face.stub(:picture, ->(_) { flunk("picture work started after a failed turn") }) { face.send(:answer, "Bug and ember lay out.") }
    text = rows_of(face.screen(24, 80, 1.0)).values.join("\n")
    assert_includes text, "talk0: empty response"
  end

  def test_successful_turn_can_start_picture_work
    face = Master::CLI::Face::Window.new(
      turn: ->(_) { Master::Result.ok("Reply") },
      ear: Quiet.new(false),
      mouth: Quiet.new(false),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] }
    )
    pictured = nil
    face.stub(:picture, ->(text) { pictured = text }) { face.send(:answer, "Bug and ember lay out.") }
    assert_equal "Bug and ember lay out.", pictured
  end

  def test_face_cancellation_kills_turn_children_and_publishes_interrupt
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    face = Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear: Quiet.new(nil),
      mouth: Quiet.new(nil),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
      event_bus: bus
    )

    order = []
    worker = Object.new
    worker.define_singleton_method(:kill) { order << :kill }
    worker.define_singleton_method(:join) { |*| order << :join; true }
    children = Object.new
    children.define_singleton_method(:kill_all) { order << :children }

    result = face.send(:cancel_worker, worker, children)

    assert result.err?
    assert_equal :timeout, result.category
    assert_equal %i[kill children join], order
    assert_equal [["user:interrupt", { reason: "face", source: "face", children: children }]], events
  end

  def test_face_falls_back_to_native_speech_when_synthesis_is_missing
    spoken = []
    mouth = Master::CLI::Face::Mouth.new(
      device: Object.new.tap { |d| d.define_singleton_method(:android?) { false } },
      synthesize: ->(_) { nil },
    )
    mouth.stub(:direct_speech?, true) do
      mouth.stub(:direct_speak, ->(text) { spoken << text; true }) do
        Master::Voice::Playback.stub(:enabled?, true) do
          Master::Voice::Playback.stub(:player, ["/usr/bin/afplay", []]) do
            Master::Voice::Speech.stub(:available?, true) do
              Master::Voice::Speech.stub(:chunks, ["hello"]) do
                assert mouth.say("hello", on_level: ->(_level) {})
              end
            end
          end
        end
      end
    end
    assert_equal ["hello"], spoken
  end

  def test_face_falls_back_to_native_speech_when_audio_player_fails
    spoken = []
    mouth = Master::CLI::Face::Mouth.new(
      device: Object.new.tap { |d| d.define_singleton_method(:android?) { false } },
      synthesize: ->(_) { "/tmp/fake-face-tts.mp3" },
    )
    File.write("/tmp/fake-face-tts.mp3", "audio")
    mouth.stub(:direct_speech?, true) do
      mouth.stub(:direct_speak, ->(text) { spoken << text; true }) do
        mouth.stub(:play, false) do
          Master::Voice::Playback.stub(:enabled?, true) do
            Master::Voice::Playback.stub(:player, ["/usr/bin/afplay", []]) do
              Master::Voice::Speech.stub(:available?, true) do
                Master::Voice::Speech.stub(:chunks, ["hello"]) do
                  assert mouth.say("hello", on_level: ->(_level) {})
                end
              end
            end
          end
        end
      end
    end
    assert_equal ["hello"], spoken
  ensure
    File.delete("/tmp/fake-face-tts.mp3") if File.exist?("/tmp/fake-face-tts.mp3")
  end

  def test_android_face_falls_back_to_termux_tts_when_synthesis_is_missing
    spoken = []
    mouth = Master::CLI::Face::Mouth.new(
      device: Object.new.tap { |d| d.define_singleton_method(:android?) { true } },
      synthesize: ->(_) { nil },
    )

    Master::Voice::Playback.stub(:enabled?, true) do
      Master::Voice::Speech.stub(:available?, true) do
        Master::Voice::Speech.stub(:chunks, ["hello"]) do
          Master::Device::Audio.stub(:available?, true) do
            Master::Device::Audio.stub(:speak, ->(text) { spoken << text; true }) do
              refute mouth.send(:direct_speech?)
              assert mouth.say("hello", on_level: ->(_level) {})
            end
          end
        end
      end
    end

    assert_equal ["hello"], spoken
  end

  def test_face_keeps_audio_failure_visible
    mouth = Quiet.new(nil)
    face = Master::CLI::Face::Window.new(
      turn: ->(_) { Master::Result.ok("Reply") },
      ear: Quiet.new(false),
      mouth:,
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] }
    )
    mouth.define_singleton_method(:say) { |*| false }
    mouth.define_singleton_method(:last_error) { "voice0: audio did not play" }

    face.send(:answer, "hello")
    text = rows_of(face.screen(24, 80, 1.0)).values.join("\n")

    assert_includes text, "voice0: audio did not play"
  end

  def test_speaking_does_not_arm_the_microphone
    face = Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear: Quiet.new(nil),
      mouth: Quiet.new(nil),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] }
    )
    face.send(:set, :speaking, ["reply"])
    face.send(:arm_ear)
    assert_nil face.instance_variable_get(:@hearing)
  end

  class FakeBus
    attr_reader :patterns
    def initialize = @patterns = {}
    def subscribe(pattern, &handler)
      (@patterns[pattern] ||= []) << handler
      -> { @patterns[pattern].delete(handler) }
    end
    def publish(event)
      @patterns.each_value { |handlers| handlers.each { |handler| handler.call(event: event) } }
    end
  end

  def test_terminal_face_subscribes_to_runtime_event_families
    bus = FakeBus.new
    face = Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear: Quiet.new(nil),
      mouth: Quiet.new(nil),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
      event_bus: bus
    )
    assert_equal %w[council:** llm:** phantom:** pipeline:** tts:**], bus.patterns.keys.sort
    bus.publish("pipeline:stage_start")
    assert_equal [:thinking], face.instance_variable_get(:@events)
    bus.publish("tts:anticipate")
    assert_equal [:thinking, :anticipate], face.instance_variable_get(:@events)
    face.send(:unsubscribe_from_bus)
    bus.publish("council:deliberation")
    assert_equal [:thinking], face.instance_variable_get(:@events)
  end

  def test_face_command_arguments_are_recognised
    assert Master::CLI::Face::Window.asked?(["/face"])
    assert Master::CLI::Face::Window.asked?(["face"])
    refute Master::CLI::Face::Window.asked?(["hello"])
    refute Master::CLI::Face::Window.asked?(["/face", "extra"])
  end
  def test_transcendent_face_keeps_one_continuous_take
    mouth = Master::CLI::Face::Mouth.new(
      device: Object.new.tap { |d| d.define_singleton_method(:android?) { false } },
    )

    Master::Voice::Speech.stub(:synthesis_mode, "transcendent") do
      Master::Voice::Speech.stub(:chunks, ["one.", "two."]) do
        assert_equal ["one. two."], mouth.send(:chunks, "one. two.")
      end
    end
  end

  def test_classic_face_retains_sentence_chunking
    mouth = Master::CLI::Face::Mouth.new(
      device: Object.new.tap { |d| d.define_singleton_method(:android?) { false } },
    )

    Master::Voice::Speech.stub(:synthesis_mode, "classic") do
      Master::Voice::Speech.stub(:chunks, ["one.", "two."]) do
        assert_equal ["one.", "two."], mouth.send(:chunks, "one. two.")
      end
    end
  end

  def test_cli_mouth_smooths_envelope_attacks_and_releases
    mouth = Master::CLI::Face::Mouth.new(
      device: Object.new.tap { |d| d.define_singleton_method(:android?) { false } },
    )
    frame = [0] * 200
    loud = [10_000] * 200
    levels = mouth.send(:levels, frame + loud + frame + loud)

    assert_in_delta 0.55, levels[1], 0.01
    assert_operator levels[2], :>, 0.40
    assert_operator levels[3], :>, levels[1]
    assert_operator levels[3], :<, 1.0
  end

end