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

  def test_the_face_uses_the_full_viewport
    painted = rows_of(window.screen(30, 60, 2.0))
    head_rows = painted.select { |_, text| text.match?(BRAILLE) }.keys
    refute_empty head_rows
    assert_operator head_rows.max, :>, 10
  end

  def test_every_row_of_the_window_is_painted
    assert_equal (1..30).to_a, rows_of(window.screen(30, 60, 2.0)).keys.sort
  end

  def test_the_renderer_receives_the_full_terminal_height
    seen_rows = nil
    renderer = ->(**kwargs) do
      seen_rows = kwargs.fetch(:rows)
      Array.new(seen_rows, " ").join("\n")
    end
    Master::CLI::Face.stub(:frame, renderer) { window.screen(30, 60, 2.0) }
    assert_equal 30, seen_rows
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

  def test_the_column_under_the_head_keeps_three_jobs
    face = window
    5.times { |i| face.send(:note_job, ["job #{i}"]) }
    text = rows_of(face.screen(30, 60, 2.0)).values.join("\n")
    assert_includes text, "job 4"
    assert_includes text, "job 2"
    refute_includes text, "job 1"
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
    assert_equal %w[council:** llm:** phantom:** pipeline:**], bus.patterns.keys.sort
    bus.publish("pipeline:stage_start")
    assert_equal [:thinking], face.instance_variable_get(:@events)
    face.send(:unsubscribe_from_bus)
    bus.publish("council:deliberation")
    assert_equal [:thinking], face.instance_variable_get(:@events)
  end

  def test_face_turn_keeps_the_structured_result
    container = Object.new
    calls = []
    turn = Master::CLI::Face::Window.turn { container }

    Master::CLI::TurnRouter.stub(
      :call,
      ->(message:, container:) { calls << [message, container]; Master::Result.ok(rendered: "trace", core: { summary: "final answer" }) },
    ) do
      result = turn.call("check this")
      assert_predicate result, :ok?
    end

    assert_equal [["check this", container]], calls
  end

  def test_face_speaks_a_fold_summary_not_its_execution_trace
    result = Master::Result.ok(
      rendered: "fold0: complete, 4 turns\n0: read -> ok\nfinal answer",
      core: { summary: "final answer" },
    )
    assert_equal "final answer", Master::CLI::Face::Window.allocate.send(:reply_text, result)
  end

  def test_face_command_arguments_are_recognised
    assert Master::CLI::Face::Window.asked?(["/face"])
    assert Master::CLI::Face::Window.asked?(["face"])
    refute Master::CLI::Face::Window.asked?(["hello"])
    refute Master::CLI::Face::Window.asked?(["/face", "extra"])
  end
end
