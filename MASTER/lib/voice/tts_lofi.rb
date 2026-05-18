# frozen_string_literal: true

module Master
  module Voice
  module TtsLofi
    ENGINES = {
      kokoro_82m: {
        license: "Apache-2.0",
        strengths: %i[fast efficient commercial browser_client_side],
        latency_ms: 300,
        voice_cloning: false,
        default: true
      },
      openvoice_v2: {
        license: "MIT",
        strengths: %i[voice_cloning commercial emotion_accent_rhythm],
        latency_ms: 125,
        voice_cloning: true
      },
      cosyvoice_2: {
        license: "check_upstream",
        strengths: %i[streaming low_latency pronunciation],
        latency_ms: 150,
        voice_cloning: true
      },
      xtts_v2: {
        license: "non_commercial",
        strengths: %i[multilingual streaming voice_cloning],
        latency_ms: 150,
        voice_cloning: true
      },
      fish_speech: {
        license: "non_commercial_cc_by_nc_sa",
        strengths: %i[emotion_tags creative multilingual],
        realtime_factor: "1:7",
        voice_cloning: true
      }
    }.freeze

    VOICE_LOFI = {
      default: {
        mode: :clean,
        reason: "clean neural speech is highest quality and safest for accessibility"
      },
      tts_vintage: {
        processor: :ffmpeg,
        preset: :tts_vintage,
        bit_depth: 12,
        sample_rate_hz: 16_000,
        lowpass_hz: 6_000,
        noise_db: -30,
        reason: "character without destroying intelligibility"
      },
      intelligible_crush: {
        processor: :ffmpeg,
        preset: :intelligible_crush,
        bit_depth: 12,
        sample_rate_hz: 22_000,
        lowpass_hz: 8_000,
        noise_db: -35,
        reason: "subtle vintage edge for spoken UI"
      },
      phone: {
        processor: :ffmpeg,
        preset: :phone,
        bandpass_hz: 300..3_400,
        reason: "radio/phone character for effect voices"
      },
      sonitex: {
        processor: :sox,
        preset: :subtle_vintage,
        reason: "cumulative lo-fi chain when SoX is available"
      }
    }.freeze

    BUFFER_POLICY = {
      target_samples: 128,
      acceptable_samples: [64, 128, 512],
      max_realtime_cpu: 0.70,
      default_clean_audio: true,
      effects_opt_in: true,
      graceful_dependency_fallback: true
    }.freeze

    module_function

    def engine(name = :kokoro_82m)
      ENGINES.fetch(name.to_sym)
    end

    def effect(name = :default)
      VOICE_LOFI.fetch(name.to_sym)
    end

    def processor_for(effect_name)
      effect(effect_name).fetch(:processor, :none)
    end

    def command(input, output, effect_name: :tts_vintage)
      profile = effect(effect_name)
      case profile[:processor]
      when :ffmpeg
        FfmpegLofi.new.command(input, output, preset: profile.fetch(:preset))
      when :sox
        Sonitex.command(input, output, preset: profile.fetch(:preset))
      else
        nil
      end
    end

    def process(input, output, effect_name: :tts_vintage)
      profile = effect(effect_name)
      case profile[:processor]
      when :ffmpeg
        FfmpegLofi.new.process(input, output, preset: profile.fetch(:preset))
      when :sox
        Sonitex.process(input, output, preset: profile.fetch(:preset))
      else
        input
      end
    end

    def brief
      <<~TEXT.strip
        TTS lofi policy:
        - default to clean audio; effects are opt-in and must degrade gracefully.
        - Kokoro-82M profile is preferred for efficient commercial clean TTS; OpenVoice V2 for MIT voice cloning.
        - For voice lofi, prefer FFmpeg acrusher 12-bit with anti-aliasing, 16-22kHz voice bandwidth, lowpass 5-8kHz.
        - Keep crackle/hiss below speech (-35dB to -25dB), never mask speech or screen readers.
        - Use 64-128 sample buffers for interactive playback, keep CPU below 70%.
      TEXT
    end
  end
  end
end
