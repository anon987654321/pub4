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

    ZERO_RATE = "+0%"
    ZERO_PITCH = "+0Hz"
    BASE_VOLUME = "volume=0.72"   # master voice volume -- slightly pulled back

    # Engine selection priority
    ENGINES = %i[piper edge replicate].freeze

    # FFmpeg effect presets. All include BASE_VOLUME for consistent loudness.
    STREAM_EFFECTS = {
      dark:      "asetrate=44100*0.8,atempo=1.25,bass=g=10,#{BASE_VOLUME}",
      demon:     "asetrate=44100*0.7,atempo=1.4,bass=g=15,acompressor=threshold=0.08:ratio=12,#{BASE_VOLUME}",
      robot:     "asetrate=44100*0.9,atempo=1.1,flanger,tremolo=f=10:d=0.5,#{BASE_VOLUME}",
      radio:     "highpass=f=300,lowpass=f=3000,acompressor=threshold=0.1:ratio=8,#{BASE_VOLUME}",
      telephone: "highpass=f=400,lowpass=f=3400,#{BASE_VOLUME}",
      underwater:"asetrate=44100*0.6,atempo=1.6,lowpass=f=800,chorus=0.5:0.9:50:0.4:0.25:2,#{BASE_VOLUME}",
      ghost:     "asetrate=44100*0.75,atempo=1.33,areverse,aecho=0.8:0.88:60:0.4,areverse,#{BASE_VOLUME}",
      cave:      "aecho=0.8:0.9:1000:0.3,#{BASE_VOLUME}",
      vinyl:     "highpass=f=100,lowpass=f=8000,aecho=0.9:0.7:20:0.15,#{BASE_VOLUME}",
      deep:      "asetrate=44100*0.82,atempo=1.22,bass=g=12,#{BASE_VOLUME}",
      choir:     "aecho=0.8:0.88:60:0.4,aecho=0.8:0.7:120:0.2,#{BASE_VOLUME}",
    }.freeze

    # Voice styles (rate/pitch for Edge TTS)
    STYLES = {
      normal:  { rate: ZERO_RATE,  pitch: ZERO_PITCH }.freeze,
      fast:    { rate: "+25%",     pitch: ZERO_PITCH }.freeze,
      slow:    { rate: "-20%",     pitch: ZERO_PITCH }.freeze,
      high:    { rate: ZERO_RATE,  pitch: "+50Hz"    }.freeze,
      low:     { rate: ZERO_RATE,  pitch: "-50Hz"    }.freeze,
      deep:    { rate: "-15%",     pitch: "-100Hz"   }.freeze,
      excited: { rate: "+15%",     pitch: "+30Hz"    }.freeze,
      calm:    { rate: "-10%",     pitch: "-20Hz"    }.freeze,
      whisper: { rate: "-15%",     pitch: "-30Hz"    }.freeze,
      urgent:  { rate: "+30%",     pitch: "+20Hz"    }.freeze,
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

    # Edge TTS voices
    # Norwegian: Pernille (female, primary) + Finn (male)
    # Dark English: Davis (US) + Ryan (GB) with :deep style
    # Malaysian English: Osman (en-MY) + Yasmin (en-MY female)
    EDGE_VOICES = {
      # Norwegian
      pernille:  "nb-NO-PernilleNeural",  # Norwegian female -- primary
      finn:      "nb-NO-FinnNeural",       # Norwegian male
      # US English
      aria:      "en-US-AriaNeural",
      jenny:     "en-US-JennyNeural",
      guy:       "en-US-GuyNeural",
      davis:     "en-US-DavisNeural",      # dark US male
      # British
      sonia:     "en-GB-SoniaNeural",
      ryan:      "en-GB-RyanNeural",       # dark GB male
      # Malaysian English
      osman:     "en-MY-OsmanNeural",      # dark Malay male
      yasmin:    "en-MY-YasminNeural",     # Malay female
    }.freeze

    # Named voice+style personas for speak(persona: :x) convenience
    VOICE_PERSONAS = {
      norwegian:   { voice: :pernille, style: :slow    }.freeze,  # female heavy Norwegian
      dark_english:{ voice: :davis,    style: :deep    }.freeze,  # dark deep US English
      dark_malay:  { voice: :osman,    style: :deep    }.freeze,  # dark deep Malaysian English
      default:     { voice: :pernille, style: :normal  }.freeze,
    }.freeze

    # Speak a short status message with a random fun voice style
    def chatter(text, style: STYLES.keys.sample, **opts)
      speak(text, style: style, **opts)
    end

    # Speak text using best available engine.
    # persona: :norwegian | :dark_english | :dark_malay (overrides voice/style)
    def speak(text, engine: nil, voice: nil, style: :normal, persona: :dark_malay, play: true)
      return Result.err("Empty text.") if text.nil? || text.strip.empty?

      text = preprocess_for_speech(text)
      return Result.err("Empty text after preprocessing.") if text.empty?

      if (p = VOICE_PERSONAS[persona.to_sym])
        voice ||= p[:voice]
        style = p[:style] if style == :normal
      end

      engine ||= best_engine
      return Result.err("No TTS engine available.") unless engine

      case engine
      when :piper     then speak_piper(text, voice: voice, preset: style, play: play)
      when :edge      then speak_edge(text, voice: voice, style: style, play: play)
      when :replicate then speak_replicate(text, play: play)
      else Result.err("Unknown engine: #{engine}")
      end
    end

    # Strip markdown/code so TTS doesn't read backticks and asterisks
    def preprocess_for_speech(text)
      t = text.to_s.dup
      t.gsub!(/```[\s\S]*?```/, "")           # fenced code blocks
      t.gsub!(/`[^`]+`/, "")                  # inline code
      t.gsub!(/\*\*([^*]+)\*\*/, '\1')        # bold
      t.gsub!(/\*([^*]+)\*/, '\1')            # italic
      t.gsub!(/^#+\s+/, "")                   # headings
      t.gsub!(/^\s*[-*]\s+/, "")              # bullets
      t.gsub!(/\[([^\]]+)\]\([^)]+\)/, '\1') # links
      t.gsub!(/\n{2,}/, ". ")                 # paragraph breaks → pause
      t.gsub!(/\n/, " ")
      t.squeeze!(" ")
      t.strip
    end
  end
end
