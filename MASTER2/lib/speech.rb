# frozen_string_literal: true

require "fileutils"
require "securerandom"
require_relative "speech/backends"
require_relative "speech/playback"
require_relative "speech/streaming"
require_relative "speech/utils"

module MASTER
  # Speech - Unified TTS interface with multiple engines
  # Priority: Piper (local) -> Edge (free cloud) -> Replicate (paid cloud)
  # Stream mode uses FFmpeg for real-time effects
  module Speech
    module_function

    extend Backends
    extend Playback
    extend Streaming
    extend Utils

    ZERO_RATE   = "+0%"
    ZERO_PITCH  = "+0Hz"
    BASE_VOLUME = "volume=0.72"

    # Engine selection priority
    ENGINES = %i[piper edge replicate].freeze

    # FFmpeg effect presets — all include BASE_VOLUME for consistent loudness
    STREAM_EFFECTS = {
      dark:       "asetrate=44100*0.8,atempo=1.25,bass=g=10,#{BASE_VOLUME}",
      demon:      "fc:[0:a]asplit=2[a][b];[b]asetrate=22050,atempo=2.0,volume=0.12[sub];[a]asetrate=28665,atempo=1.54,bass=g=22,treble=g=-14,aecho=0.6:0.72:88:0.30,chorus=0.5:0.6:50:0.28:0.2:1.6[proc];[proc][sub]amix=inputs=2:weights=1 0.22:normalize=0[mix];[mix]acompressor=threshold=0.04:ratio=20:attack=5:release=50,extrastereo=m=2.5,#{BASE_VOLUME}[out]",
      robot:      "asetrate=44100*0.9,atempo=1.1,flanger,tremolo=f=10:d=0.5,#{BASE_VOLUME}",
      radio:      "highpass=f=300,lowpass=f=3000,acompressor=threshold=0.1:ratio=8,#{BASE_VOLUME}",
      telephone:  "highpass=f=400,lowpass=f=3400,#{BASE_VOLUME}",
      underwater: "asetrate=44100*0.6,atempo=1.6,lowpass=f=800,chorus=0.5:0.9:50:0.4:0.25:2,#{BASE_VOLUME}",
      ghost:      "asetrate=44100*0.75,atempo=1.33,areverse,aecho=0.8:0.88:60:0.4,areverse,#{BASE_VOLUME}",
      velvet:     "asetrate=44100*0.84,atempo=1.19,bass=g=9,acompressor=threshold=0.085:ratio=9,chorus=0.45:0.9:32:0.25:0.2:1.6,#{BASE_VOLUME}",
      cave:       "aecho=0.8:0.9:1000:0.3,#{BASE_VOLUME}",
      vinyl:      "highpass=f=100,lowpass=f=8000,aecho=0.9:0.7:20:0.15,#{BASE_VOLUME}",
      deep:       "asetrate=44100*0.82,atempo=1.22,bass=g=12,#{BASE_VOLUME}",
      choir:      "aecho=0.8:0.88:60:0.4,aecho=0.8:0.7:120:0.2,#{BASE_VOLUME}",
      stadium:    "aecho=0.8:0.7:300:0.25,aecho=0.7:0.6:800:0.15,#{BASE_VOLUME}",
    }.freeze

    # Voice styles (rate/pitch for Edge TTS)
    STYLES = {
      normal:    { rate: ZERO_RATE, pitch: ZERO_PITCH }.freeze,
      fast:      { rate: "+25%",    pitch: ZERO_PITCH }.freeze,
      slow:      { rate: "-25%",    pitch: "-60Hz"    }.freeze,
      high:      { rate: ZERO_RATE, pitch: "+50Hz"    }.freeze,
      low:       { rate: "-10%",    pitch: "-80Hz"    }.freeze,
      deep:      { rate: "-35%",    pitch: "-150Hz"   }.freeze,
      heavy:     { rate: "-30%",    pitch: "-120Hz"   }.freeze,
      cinematic: { rate: "-22%",    pitch: "-95Hz"    }.freeze,
      excited:   { rate: "+15%",    pitch: "+30Hz"    }.freeze,
      calm:      { rate: "-15%",    pitch: "-30Hz"    }.freeze,
      whisper:   { rate: "-20%",    pitch: "-40Hz"    }.freeze,
      urgent:    { rate: "+30%",    pitch: "+20Hz"    }.freeze,
    }.freeze

    # Piper voice presets (length_scale/noise_scale)
    PIPER_PRESETS = {
      normal:      { length_scale: 1.0, noise_scale: 0.667 }.freeze,
      chipmunk:    { length_scale: 0.6, noise_scale: 0.667 }.freeze,
      zombie:      { length_scale: 2.5, noise_scale: 0.4   }.freeze,
      robot:       { length_scale: 1.0, noise_scale: 0.1   }.freeze,
      manic:       { length_scale: 0.8, noise_scale: 0.9   }.freeze,
      calm:        { length_scale: 1.2, noise_scale: 0.3   }.freeze,
      urgent:      { length_scale: 0.7, noise_scale: 0.5   }.freeze,
      demon:       { length_scale: 3.0, noise_scale: 0.3   }.freeze,
      caffeinated: { length_scale: 0.5, noise_scale: 0.7   }.freeze,
    }.freeze

    # Edge TTS voices (Microsoft Neural TTS)
    EDGE_VOICES = {
      # Norwegian
      pernille: "nb-NO-PernilleNeural",
      finn:     "nb-NO-FinnNeural",
      # US English
      aria:     "en-US-AriaNeural",
      jenny:    "en-US-JennyNeural",
      guy:      "en-US-GuyNeural",
      davis:    "en-US-DavisNeural",
      steffan:  "en-US-SteffanNeural",
      # British
      sonia:    "en-GB-SoniaNeural",
      ryan:     "en-GB-RyanNeural",
      libby:    "en-GB-LibbyNeural",
      # Malaysian English
      osman:    "ms-MY-OsmanNeural",
      yasmin:   "en-MY-YasminNeural",
      # Australian
      natasha:  "en-AU-NatashaNeural",
      william:  "en-AU-WilliamNeural",
      # Irish
      emily:    "en-IE-EmilyNeural",
      # South African
      leah:     "en-ZA-LeahNeural",
    }.freeze

    # Named voice+style personas
    VOICE_PERSONAS = {
      norwegian:    { voice: :pernille, style: :slow  }.freeze,
      dark_english: { voice: :davis,    style: :deep  }.freeze,
      dark_malay:   { voice: :osman,    style: :deep  }.freeze,
      british:      { voice: :ryan,     style: :heavy }.freeze,
      australian:   { voice: :natasha,  style: :slow  }.freeze,
      irish:        { voice: :emily,    style: :calm  }.freeze,
      default:      { voice: :osman,    style: :deep  }.freeze,
    }.freeze

    @session_persona = :dark_malay

    class << self
      attr_accessor :session_persona
    end

    # Speak text using best available engine.
    # persona: key from VOICE_PERSONAS; nil uses session_persona (:dark_malay by default)
    def speak(text, engine: nil, voice: nil, style: :normal, persona: nil, play: true)
      return Result.err("Empty text.") if text.nil? || text.strip.empty?

      engine ||= Utils.best_engine
      unless engine
        hint = "install piper/edge-tts or set REPLICATE_API_TOKEN"
        return Result.err("No TTS engine available. #{hint}")
      end

      active_persona = persona ? persona.to_sym : (@session_persona || :dark_malay)
      if (p = VOICE_PERSONAS[active_persona])
        voice ||= p[:voice]
        style = p[:style] if style == :normal
      end

      case engine
      when :piper    then speak_piper(text, voice: voice, preset: style, play: play)
      when :edge     then speak_edge(text, voice: voice, style: style, play: play)
      when :replicate then speak_replicate(text, play: play)
      else Result.err("Unknown engine: #{engine}")
      end
    end
  end
end
