# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/voice/vad"

class TestVoiceVad < Minitest::Test
  def setup
    @t = 0
    @vad = Master::Voice::Vad.new(
      backend: Master::Voice::Vad::EnergyBackend.new,
      config: { backend: :energy },
      clock_ms: -> { @t },
    )
    @events = []
    @vad.on_event { |e| @events << e }
  end

  def silence(n = Master::Voice::Vad::FRAME_SAMPLES)
    Array.new(n, 0.0)
  end

  def tone(amplitude, n = Master::Voice::Vad::FRAME_SAMPLES)
    rate = Master::Voice::Vad::SAMPLE_RATE
    Array.new(n) { |i| amplitude * Math.sin(2 * Math::PI * 220 * i / rate) }
  end

  def advance(ms = Master::Voice::Vad::FRAME_MS)
    @t += ms
  end

  def test_build_defaults_to_energy_without_silero
    vad = Master::Voice::Vad.build(config: { backend: :energy })
    assert_equal :energy, vad.backend_name
  end

  def test_silence_is_not_speech
    10.times do
      frame = @vad.process(silence)
      refute frame.speech?
      advance
    end
    assert_empty @events
  end

  def test_speech_start_after_min_duration
    amp = 0.2
    # First frame only sets speech_started_at; duration is measured on later
    # frames. Need (n-1)*FRAME_MS >= min_speech_ms.
    frames_before = (250.0 / Master::Voice::Vad::FRAME_MS).ceil
    frames_before.times do
      @vad.process(tone(amp))
      advance
    end
    assert_empty @events.select { |e| e.name == :speech_start }

    @vad.process(tone(amp))
    advance
    starts = @events.select { |e| e.name == :speech_start }
    assert_equal 1, starts.length
    assert @vad.speaking
  end

  def test_speech_end_after_hangover
    amp = 0.2
    20.times do
      @vad.process(tone(amp))
      advance
    end
    assert @vad.speaking

    hang_frames = (700.0 / Master::Voice::Vad::FRAME_MS).ceil + 1
    hang_frames.times do
      @vad.process(silence)
      advance
    end
    ends = @events.select { |e| e.name == :speech_end }
    assert_equal 1, ends.length
    refute @vad.speaking
  end

  def test_barge_in_mode_is_stricter
    @vad.mode!(:barge_in)
    soft = 0.05
    20.times do
      @vad.process(tone(soft))
      advance
    end
    assert_empty @events.select { |e| e.name == :speech_start }
  end

  def test_pcm16_accepted
    samples = Array.new(Master::Voice::Vad::FRAME_SAMPLES, 8_000)
    frame = @vad.process(samples)
    assert frame.probability > 0.5
  end

  def test_reset_clears_speaking
    15.times do
      @vad.process(tone(0.2))
      advance
    end
    assert @vad.speaking
    @vad.reset!
    refute @vad.speaking
    assert_equal 0.0, @vad.snapshot[:probability]
  end

  def test_invalid_mode_rejected
    assert_raises(ArgumentError) { @vad.mode!(:nonsense) }
  end

  def test_snapshot_frozen
    assert @vad.snapshot.frozen?
  end

  def test_frame_reports_backend
    frame = @vad.process(silence)
    assert_equal :energy, frame.backend
  end

  def test_hysteresis_band_does_not_end_speech_immediately
    amp = 0.2
    15.times do
      @vad.process(tone(amp))
      advance
    end
    assert @vad.speaking

    # Mid-band energy: between silence_threshold and speech_threshold after
    # mapping — use very quiet but non-zero so we stay in band or drop slowly.
    # One quiet frame must not end speech (hangover required).
    @vad.process(tone(0.0001))
    advance
    assert @vad.speaking
    assert_empty @events.select { |e| e.name == :speech_end }
  end
end
