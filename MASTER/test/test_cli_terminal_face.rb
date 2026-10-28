# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face"
require_relative "../lib/cli/face/window"

class TestCliTerminalFace < Minitest::Test
  Quiet = Struct.new(:missing) do
    def available? = missing.nil?
  end

  # Braille is retired: the face is plain ASCII.
  BRAILLE = /[\u2800-\u28FF]/
  CONTOUR = %r{[|/\\\-]}

  def window
    Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear: Quiet.new(nil),
      mouth: Quiet.new(nil),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [30, 60] },
    )
  end

  def rows_of(screen)
    screen.scan(/\e\[(\d+);1H(.*?)\e\[K/).to_h do |row, text|
      [row.to_i, text.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")]
    end
  end

  def test_the_face_owns_the_stage_and_control_strip
    shown = rows_of(window.screen(30, 80, 2.0)).values.join("\n")

    assert_match CONTOUR, shown
    refute_match BRAILLE, shown
    assert_includes shown, "idle, mic on"
    refute_includes shown, "/ FACE"
    refute_includes shown, "recent"
  end

  def test_depth_is_bold_near_and_dim_far_in_colour_terminals
    head = Master::CLI::Face::Head.for(20, 40)
    frame = Master::CLI::Face::Ascii.new(head, 20, 40).render(Master::CLI::Face::Motion.rest)

    assert_match(/\e\[0;1;38;2;\d+;\d+;\d+m/, frame.to_s(color: true))
    assert_match(/\e\[0;2;38;2;\d+;\d+;\d+m/, frame.to_s(color: true))
    refute_includes frame.to_s, "\e"
  end

  def test_the_cursor_sits_on_the_prompt_line_after_the_draft
    # A fixed prompt: the fallback names this host and checkout, which can outrun a 40-column window.
    face = Master::CLI::Face::Window.new(
      turn: ->(_line) {}, ear: Quiet.new(nil), mouth: Quiet.new(nil),
      input: StringIO.new, output: StringIO.new, size: -> { [30, 60] }, prompt: -> { "master0:~$" }
    )
    [[30, 80], [24, 60], [12, 40]].each do |rows, cols|
      screen = face.screen(rows, cols, 1.0)
      row, col = screen.scan(/\e\[(\d+);(\d+)H\e\[\?25h\z/).first.map(&:to_i)
      prompt = rows_of(screen).fetch(row)

      assert prompt.start_with?("#{face.send(:operator_prompt)} "), "row #{row} of #{rows} is not the prompt: #{prompt.inspect}"
      assert_equal prompt.length + 1, col, "the cursor follows the draft"
    end
  end

  def test_every_row_of_the_window_is_painted
    assert_equal (1..30).to_a, rows_of(window.screen(30, 80, 2.0)).keys.sort
  end

  def test_the_renderer_receives_the_controlled_height_and_the_width_sizing_gives
    seen = nil
    renderer = ->(**kwargs) do
      seen = [kwargs.fetch(:rows), kwargs.fetch(:cols)]
      Array.new(seen.first, " " * seen.last).join("\n")
    end
    Master::CLI::Face.stub(:frame, renderer) { window.screen(30, 80, 2.0) }
    assert_equal Master::CLI::Face::Sizing.fit(23, 80), seen
    assert_equal 23, seen.first
    assert_operator seen.last, :<=, 76, "two columns of margin a side"
  end

  def test_ctrl_v_toggles_constitutional_law_glyphs_without_entering_the_prompt
    face = window
    assert_equal true, face.instance_variable_get(:@law_field_visible)

    face.send(:react, "\u0016")
    assert_equal false, face.instance_variable_get(:@law_field_visible)
    assert_empty face.instance_variable_get(:@draft)
    assert_includes face.instance_variable_get(:@words).join(" "), "hidden"

    face.send(:react, "\u0016")
    assert_equal true, face.instance_variable_get(:@law_field_visible)
    assert_empty face.instance_variable_get(:@draft)
    assert_includes face.instance_variable_get(:@words).join(" "), "visible"
    glyph = Master::Face::LawField.laws.first.fetch("glyph")
    assert_includes face.instance_variable_get(:@words).join(" "), glyph
  end

  def test_terminal_law_toggle_is_passed_to_the_shared_face_renderer
    face = window
    seen = []
    renderer = lambda do |**kwargs|
      seen << kwargs.fetch(:show_laws)
      Array.new(kwargs.fetch(:rows), " " * kwargs.fetch(:cols)).join("\n")
    end
    face.send(:react, "\u0016")

    Master::CLI::Face.stub(:frame, renderer) { face.screen(30, 80, 2.0) }

    assert_equal [false], seen
  end

  def test_terminal_law_ring_cannot_be_enabled_when_laws_disable_it
    face = window
    face.instance_variable_set(:@law_field_visible, false)

    Master::Face::LawField.stub(:config, { "terminal_law_ring" => false }) do
      face.send(:react, "\u0016")
    end

    refute face.instance_variable_get(:@law_field_visible)
    assert_includes face.instance_variable_get(:@words).join(" "), "disabled by laws.yml"
  end

  def test_law_toggle_remains_available_while_microphone_is_armed
    face = window
    hearing = Object.new
    hearing.define_singleton_method(:alive?) { true }
    face.instance_variable_set(:@hearing, hearing)

    face.send(:react, "\u0016")

    assert_equal false, face.instance_variable_get(:@law_field_visible)
    refute face.instance_variable_get(:@halt_ear), "display toggles should not stop a listening turn"
  end

  def test_ctrl_c_interrupts_or_clears_without_leaving_the_face
    face = window

    face.send(:react, "\u0003")

    refute face.instance_variable_get(:@closing)
    assert_includes face.instance_variable_get(:@words).join(" "), "interrupted"
  end

  def test_ctrl_c_clears_a_draft_but_keeps_the_face_open
    face = window
    face.send(:react, "h")
    face.send(:react, "i")

    face.send(:react, "\u0003")

    refute face.instance_variable_get(:@closing)
    assert_empty face.instance_variable_get(:@draft)
    assert_includes face.instance_variable_get(:@words).join(" "), "draft cleared"
  end

  def test_ctrl_d_leaves_the_face
    face = window

    face.send(:react, "\u0004")

    assert face.instance_variable_get(:@closing)
  end

  def test_face_uses_the_original_repl_prompt_when_a_provider_is_available
    prompt = "openbsd pub4 MASTER main dirty llm discover input"
    face = Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear: Quiet.new(false),
      mouth: Quiet.new(false),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
      prompt: -> { "#{prompt} " },
    )

    assert_equal prompt, face.send(:operator_prompt)
    assert_equal "#{prompt} hello", face.send(:typed, "hello", 80)
  end

  def test_ctrl_c_stop_request_is_not_lost_when_listening_starts
    stopped = nil
    ear = Object.new
    ear.define_singleton_method(:available?) { true }
    ear.define_singleton_method(:missing) { nil }
    ear.define_singleton_method(:listen) do |stop:, on_partial: nil|
      stopped = stop.call
      nil
    end
    face = Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear:,
      mouth: Quiet.new(false),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
    )
    face.instance_variable_set(:@halt_ear, true)
    face.instance_variable_set(:@suppress_heard, true)

    face.send(:listen)

    assert_equal true, stopped
    assert_includes face.instance_variable_get(:@words).join(" "), "listening interrupted"
  end

  def test_a_failed_speech_keeps_the_reply_visible
    mouth = Object.new
    mouth.define_singleton_method(:missing) { nil }
    mouth.define_singleton_method(:available?) { true }
    mouth.define_singleton_method(:say) { |*_args, **_kwargs| false }
    mouth.define_singleton_method(:last_error) { "the synthesiser returned no audio" }
    face = Master::CLI::Face::Window.new(
      turn: ->(_) { Master::Result.ok("The actual answer remains visible.") },
      ear: Quiet.new(false),
      mouth:,
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
    )

    face.send(:answer, "Tell me something useful.")

    transcript = rows_of(face.screen(24, 80, 1.0)).values.join("\n")
    assert_includes transcript, "The actual answer remains visible."
    assert_includes transcript, "reply shown as text"
    assert_includes transcript, "synthesiser returned no audio"
  end


  def test_motion_has_a_camera_dolly
    motion = Master::CLI::Face::Motion.new(seed: 7)
    motion.step(state: :idle, t: 1.0)
    thinking = motion.step(state: :thinking, t: 2.0).dolly
    assert_operator thinking, :>, 0.95
  end

  def test_motion_turns_constantly_at_rest_and_settles_to_the_front_when_attending
    motion = Master::CLI::Face::Motion.new(seed: 7)
    turns = (1..40).map { |i| motion.step(state: :idle, t: i * 0.25).turn }
    assert_in_delta Master::CLI::Face::Motion::SPIN * 0.25, turns[10] - turns[9], 0.01
    40.times { |i| motion.step(state: :listening, t: 10.0 + (i * 0.25)) }
    turn = motion.step(state: :listening, t: 20.0).turn
    assert_in_delta 0.0, Math.sin(turn / 2), 0.02
  end

  def test_motion_keeps_the_face_readable
    motion = Master::CLI::Face::Motion.new(seed: 7)
    120.times do |i|
      look = motion.step(state: :idle, t: (i + 1) / 15.0)
      assert_operator look.yaw.abs, :<=, 0.5
      assert look.dolly.between?(0.95, 1.10)
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

  def test_typed_input_fallback_remains_usable_without_a_session_prompt
    prompt = window.send(:operator_prompt)
    assert_match(/\A[^:]+:.+\$\z/, prompt)
    assert_equal "#{prompt} hello", window.send(:typed, "hello", 80)
  end

  def test_closed_terminal_streams_are_reported_as_eof
    [:readiness, :character].each do |failure|
      stream = Object.new
      if failure == :readiness
        stream.define_singleton_method(:wait_readable) { |_timeout| raise IOError, "closed stream" }
        stream.define_singleton_method(:getch) { flunk("getch must not run after readiness fails") }
      else
        stream.define_singleton_method(:wait_readable) { |_timeout| true }
        stream.define_singleton_method(:getch) { raise IOError, "closed stream" }
      end
      face = Master::CLI::Face::Window.new(
        turn: ->(_) {},
        ear: Quiet.new(nil),
        mouth: Quiet.new(nil),
        input: stream,
        output: StringIO.new,
        size: -> { [24, 80] },
      )

      assert_equal :eof, face.send(:read_key, 0), "#{failure} failure should use the ordinary EOF path"
    end
  end
  def test_run_restores_the_terminal_when_the_input_stream_closes
    stream = Object.new
    stream.define_singleton_method(:tty?) { false }
    stream.define_singleton_method(:wait_readable) { |_timeout| raise IOError, "closed stream" }
    stream.define_singleton_method(:getch) { flunk("getch must not run after readiness fails") }
    output = StringIO.new
    face = Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear: Quiet.new(nil),
      mouth: Quiet.new(nil),
      input: stream,
      output: output,
      size: -> { [24, 80] },
    )

    result = face.stub(:arm_ear, nil) { face.run }

    assert_equal "face0: closed", result
    assert_includes output.string, "\e[?1049h"
    assert_includes output.string, "\e[?1049l"
    assert_equal true, face.instance_variable_get(:@closing)
  end

  def test_a_failed_turn_does_not_start_picture_work
    face = Master::CLI::Face::Window.new(
      turn: ->(_) { Master::Result.err("talk0: empty response", category: :provider_error) },
      ear: Quiet.new(false),
      mouth: Quiet.new(false),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
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
      size: -> { [24, 80] },
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
      event_bus: bus,
    )

    order = []
    worker = Object.new
    worker.define_singleton_method(:kill) { order << :kill }
    worker.define_singleton_method(:join) { |*| order << :join; true }
    children = Object.new
    children.define_singleton_method(:kill_all) { order << :children }

    result = face.send(:cancel_worker, worker, children)

    assert result.err?
    # Ctrl-C keeps the face open, so the turn is aborted rather than timed out.
    assert_equal :abort, result.category
    assert_equal %i[kill children join], order
    assert_equal [["user:interrupt", { reason: "face", source: "face", children: }]], events

    face.instance_variable_set(:@closing, true)
    assert_equal :timeout, face.send(:cancel_worker, worker, children).category
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
    dir = Dir.mktmpdir("master-face-tts")
    audio = File.join(dir, "fake-face-tts.mp3")
    mouth = Master::CLI::Face::Mouth.new(
      device: Object.new.tap { |d| d.define_singleton_method(:android?) { false } },
      synthesize: ->(_) { audio },
    )
    File.write(audio, "audio")
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
    FileUtils.rm_rf(dir) if dir
  end

  def test_later_chunk_uses_direct_speech_when_its_synthesis_fails
    Dir.mktmpdir("master-face-mouth-fallback") do |dir|
      first_path = File.join(dir, "first.mp3")
      File.write(first_path, "fake audio")
      count = 0
      count_lock = Mutex.new
      synthesize = lambda do |_text|
        call = count_lock.synchronize { count += 1 }
        call == 1 ? first_path : nil
      end
      device = Object.new.tap { |item| item.define_singleton_method(:android?) { false } }
      mouth = Master::CLI::Face::Mouth.new(device:, synthesize:)
      played = []
      direct = []

      mouth.stub(:available?, true) do
        mouth.stub(:chunks, ["First sentence.", "Second sentence."]) do
          mouth.stub(:play, ->(_path, part, on_level:, stop:) { played << part; true }) do
            mouth.stub(:direct_speak, ->(part) { direct << part; true }) do
              Master::Voice::Playback.stub(:begin_reply_generation!, -> { true }) do
                assert mouth.say("First sentence. Second sentence.", on_level: ->(_level) {})
              end
            end
          end
        end
      end

      assert_equal ["First sentence."], played
      assert_equal ["Second sentence."], direct
    end
  end

  def test_speech_interruption_stops_later_chunks_too
    Dir.mktmpdir("master-face-mouth-interrupt") do |dir|
      first_path = File.join(dir, "first.mp3")
      second_path = File.join(dir, "second.mp3")
      File.write(first_path, "first audio")
      File.write(second_path, "second audio")
      count = 0
      count_lock = Mutex.new
      synthesize = lambda do |_text|
        call = count_lock.synchronize { count += 1 }
        call == 1 ? first_path : second_path
      end
      device = Object.new.tap { |item| item.define_singleton_method(:android?) { false } }
      mouth = Master::CLI::Face::Mouth.new(device:, synthesize:)
      played = []
      stop_checks = 0
      stop = -> { stop_checks += 1; stop_checks == 2 }

      mouth.stub(:available?, true) do
        mouth.stub(:chunks, ["First sentence.", "Second sentence."]) do
          mouth.stub(:play, lambda { |_path, part, on_level:, stop:|
            played << part
            stop.call
            true
          }) do
            mouth.stub(:direct_speak, ->(part) { flunk("speech after interruption: #{part}") }) do
              Master::Voice::Playback.stub(:begin_reply_generation!, -> { true }) do
                assert mouth.say("First sentence. Second sentence.", on_level: ->(_level) {}, stop:)
              end
            end
          end
        end
      end

      assert_equal ["First sentence."], played
      assert_equal 2, stop_checks, "the stop request stays latched and is not read again"
      refute File.exist?(second_path), "prefetched audio for the skipped chunk is cleaned up"
    end
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
      size: -> { [24, 80] },
    )
    mouth.define_singleton_method(:say) { |*| false }
    mouth.define_singleton_method(:last_error) { "voice0: audio did not play" }

    face.send(:answer, "hello")
    text = rows_of(face.screen(24, 80, 1.0)).values.join("\n")

    assert_includes text, "voice0: audio did not play"
  end

  def test_blank_microphone_transcripts_are_ignored_instead_of_sent_as_empty_messages
    ["", "  \t  "].each do |transcript|
      ear = Object.new
      ear.define_singleton_method(:missing) { nil }
      ear.define_singleton_method(:available?) { true }
      ear.define_singleton_method(:listen) { |stop:, on_partial:| transcript }

      face = Master::CLI::Face::Window.new(
        turn: ->(text) { flunk("blank microphone transcript reached turn: #{text.inspect}") },
        ear:,
        mouth: Quiet.new(nil),
        input: StringIO.new,
        output: StringIO.new,
        size: -> { [24, 80] },
      )

      face.stub(:answer, ->(text) { flunk("blank microphone transcript was answered: #{text.inspect}") }) do
        face.send(:hear)
      end

      words = face.instance_variable_get(:@words).join(" ")
      assert_equal :idle, face.instance_variable_get(:@state)
      assert_includes words, "heard nothing"
      refute_includes words, "empty message"
    end
  end

  def test_typed_interrupt_drops_late_transcript_and_returns_face_to_idle
    ear = Object.new
    ear.define_singleton_method(:missing) { nil }
    ear.define_singleton_method(:available?) { true }
    ear.define_singleton_method(:listen) { |stop:, on_partial:| "transcript after typing began" }
    face = Master::CLI::Face::Window.new(
      turn: ->(text) { flunk("interrupted transcript reached turn: #{text.inspect}") },
      ear:,
      mouth: Quiet.new(nil),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
    )
    face.instance_variable_set(:@draft, "h")
    face.instance_variable_set(:@suppress_heard, true)
    face.instance_variable_set(:@retain_input_on_interrupt, true)

    face.stub(:answer, ->(text) { flunk("interrupted transcript was answered: #{text.inspect}") }) do
      face.send(:hear)
    end

    assert_equal :idle, face.instance_variable_get(:@state)
    assert_equal "h", face.instance_variable_get(:@draft)
    assert_equal false, face.instance_variable_get(:@suppress_heard)
    assert_equal false, face.instance_variable_get(:@retain_input_on_interrupt)
    assert_includes face.instance_variable_get(:@words).join(" "), "typed input retained"
  end

  def test_speaking_does_not_arm_the_microphone
    face = Master::CLI::Face::Window.new(
      turn: ->(_) {},
      ear: Quiet.new(nil),
      mouth: Quiet.new(nil),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
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
      topic = event.to_s.split(":", 2).first
      handlers = @patterns.fetch("#{topic}:**", [])
      handlers.dup.each { |handler| handler.call(event:) }
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
      event_bus: bus,
    )
    assert_equal %w[council:** llm:** phantom:** pipeline:** tts:**], bus.patterns.keys.sort
    bus.publish("pipeline:stage_start")
    assert_equal [:thinking], face.instance_variable_get(:@events)
    bus.publish("tts:anticipate")
    assert_equal [:thinking, :anticipate], face.instance_variable_get(:@events)
    face.send(:unsubscribe_from_bus)
    bus.publish("council:deliberation")
    assert_equal [:thinking, :anticipate], face.instance_variable_get(:@events)
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
