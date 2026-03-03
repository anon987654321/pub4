# frozen_string_literal: true

require "fileutils"
require "securerandom"
require_relative "speech/backends"
require_relative "speech/playback"
require_relative "speech/streaming"
require_relative "speech/utils"

module MASTER
  # Speech - Unified TTS interface with multiple engines
  # Priority: Piper (local) -> Edge CLI (free cloud) -> espeak-ng (fallback) -> Replicate (paid)
  module Speech
    module_function

    extend Backends
    extend Playback
    extend Streaming
    extend Utils

    ZERO_RATE  = "+0%"
    ZERO_PITCH = "+0Hz"
    BASE_VOLUME = "volume=0.72"   # master voice volume

    # Engine selection priority
    ENGINES = %i[piper edge espeak replicate].freeze

    # FFmpeg effect presets — all include BASE_VOLUME for consistent loudness
    STREAM_EFFECTS = {
      dark:       "asetrate=44100*0.8,atempo=1.25,bass=g=10,#{BASE_VOLUME}",
      demon:      "asetrate=44100*0.7,atempo=1.4,bass=g=15,acompressor=threshold=0.08:ratio=12,#{BASE_VOLUME}",
      robot:      "asetrate=44100*0.9,atempo=1.1,flanger,tremolo=f=10:d=0.5,#{BASE_VOLUME}",
      radio:      "highpass=f=300,lowpass=f=3000,acompressor=threshold=0.1:ratio=8,#{BASE_VOLUME}",
      telephone:  "highpass=f=400,lowpass=f=3400,#{BASE_VOLUME}",
      underwater: "asetrate=44100*0.6,atempo=1.6,lowpass=f=800,chorus=0.5:0.9:50:0.4:0.25:2,#{BASE_VOLUME}",
      ghost:      "asetrate=44100*0.75,atempo=1.33,areverse,aecho=0.8:0.88:60:0.4,areverse,#{BASE_VOLUME}",
      cave:       "aecho=0.8:0.9:1000:0.3,#{BASE_VOLUME}",
      vinyl:      "highpass=f=100,lowpass=f=8000,aecho=0.9:0.7:20:0.15,#{BASE_VOLUME}",
      deep:       "asetrate=44100*0.82,atempo=1.22,bass=g=12,#{BASE_VOLUME}",
      choir:      "aecho=0.8:0.88:60:0.4,aecho=0.8:0.7:120:0.2,#{BASE_VOLUME}",
      stadium:    "aecho=0.8:0.7:300:0.25,aecho=0.7:0.6:800:0.15,#{BASE_VOLUME}",
      whisper_fx: "volume=0.4,asetrate=44100*1.05,atempo=0.95,#{BASE_VOLUME}",
    }.freeze

    # Voice styles (rate/pitch for Edge TTS)
    STYLES = {
      normal:  { rate: ZERO_RATE, pitch: ZERO_PITCH }.freeze,
      fast:    { rate: "+25%",    pitch: ZERO_PITCH }.freeze,
      slow:    { rate: "-25%",    pitch: "-60Hz"    }.freeze,
      high:    { rate: ZERO_RATE, pitch: "+50Hz"    }.freeze,
      low:     { rate: "-10%",    pitch: "-80Hz"    }.freeze,
      deep:    { rate: "-35%",    pitch: "-150Hz"   }.freeze,   # slow, very low — dark male default
      heavy:   { rate: "-30%",    pitch: "-120Hz"   }.freeze,   # heavy without being extreme
      excited: { rate: "+15%",    pitch: "+30Hz"    }.freeze,
      calm:    { rate: "-15%",    pitch: "-30Hz"    }.freeze,
      whisper: { rate: "-20%",    pitch: "-40Hz"    }.freeze,
      urgent:  { rate: "+30%",    pitch: "+20Hz"    }.freeze,
    }.freeze

    # Piper voice presets (length_scale/noise_scale affect prosody, not voice identity)
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

    # Piper voice model filenames (without .onnx extension)
    # Download from https://huggingface.co/rhasspy/piper-voices
    PIPER_VOICES = {
      # US English female
      lessac:       "en_US-lessac-medium",         # warm, clear (default)
      libritts:     "en_US-libritts_r-medium",     # audiobook style
      arctic:       "en_US-arctic-medium",         # CSTR ARCTIC dataset
      hfc_female:   "en_US-hfc_female-medium",     # natural female
      jenny:        "en_US-jenny_dioco-medium",    # expressive female
      # US English male
      ryan:         "en_US-ryan-high",             # smooth US male
      hfc_male:     "en_US-hfc_male-medium",       # natural male
      joe:          "en_US-joe-medium",            # friendly male
      # British English
      alan:         "en_GB-alan-low",              # British male
      cori:         "en_GB-cori-medium",           # British female
      gb_jenny:     "en_GB-jenny_dioco-medium",    # British Jenny
      northern:     "en_GB-northern_english_male-medium", # Northern UK male
      # Norwegian
      talesyntese:  "no_NO-talesyntese-medium",    # Norwegian (Bokmål)
    }.freeze

    # Edge TTS voices (Microsoft Neural TTS)
    EDGE_VOICES = {
      # Norwegian
      pernille: "nb-NO-PernilleNeural",   # Norwegian female -- heavy, primary
      finn:     "nb-NO-FinnNeural",       # Norwegian male
      # US English
      aria:     "en-US-AriaNeural",
      jenny:    "en-US-JennyNeural",
      guy:      "en-US-GuyNeural",
      davis:    "en-US-DavisNeural",      # dark US male
      steffan:  "en-US-SteffanNeural",    # serious US male
      # British
      sonia:    "en-GB-SoniaNeural",
      ryan:     "en-GB-RyanNeural",       # dark GB male
      libby:    "en-GB-LibbyNeural",      # clear GB female
      # Malaysian English
      osman:    "en-MY-OsmanNeural",      # dark Malay male (default persona)
      yasmin:   "en-MY-YasminNeural",     # Malay female
      # Australian
      natasha:  "en-AU-NatashaNeural",    # Australian female
      william:  "en-AU-WilliamNeural",    # Australian male
      # Irish
      emily:    "en-IE-EmilyNeural",      # Irish female
      # South African
      leah:     "en-ZA-LeahNeural",       # South African female
    }.freeze

    # Replicate MiniMax Speech-02 Turbo voice IDs
    REPLICATE_VOICES = {
      casual_guy:     "Casual_Guy",
      confident_lady: "Confident_Lady",
      mature_lady:    "Mature_Lady",
      wise_man:       "Wise_Man",
      young_knight:   "Young_Knight",
      calm_woman:     "Calm_Woman",
      lively_girl:    "Lively_Girl",
      deep_voice_man: "Deep_Voice_Man",
    }.freeze

    # Named voice+style personas for speak(persona: :x)
    VOICE_PERSONAS = {
      norwegian:    { voice: :pernille, style: :slow  }.freeze,
      dark_english: { voice: :davis,    style: :deep  }.freeze,
      dark_malay:   { voice: :osman,    style: :deep  }.freeze,
      british:      { voice: :ryan,     style: :heavy }.freeze,
      australian:   { voice: :natasha,  style: :slow  }.freeze,
      irish:        { voice: :emily,    style: :calm  }.freeze,
      default:      { voice: :osman,    style: :deep  }.freeze,   # dark male default
    }.freeze

    # Fixed dark male default; use persona: :norwegian etc. to override per-call
    @session_persona = :dark_malay

    class << self
      attr_accessor :session_persona
    end

    # Speak a short status message with a random fun voice style
    def chatter(text, style: STYLES.keys.sample, **opts)
      speak(text, style: style, **opts)
    end

    # Speak text using best available engine.
    # persona: key from VOICE_PERSONAS; nil = use session_persona (randomly chosen at boot)
    def speak(text, engine: nil, voice: nil, style: :normal, persona: nil, play: true)
      return Result.err("Empty text.") if text.nil? || text.strip.empty?

      text = preprocess_for_speech(text)
      return Result.err("Empty text after preprocessing.") if text.empty?

      # Resolve persona: explicit > session default > :dark_malay
      active_persona = persona ? persona.to_sym : (@session_persona || :dark_malay)
      if (p = VOICE_PERSONAS[active_persona])
        voice ||= p[:voice]
        style = p[:style] if style == :normal
      end

      engine ||= best_engine
      return Result.err("No TTS engine available.") unless engine

      case engine
      when :piper     then speak_piper(text, voice: voice, preset: style, play: play)
      when :edge      then speak_edge(text, voice: voice, style: style, play: play)
      when :espeak    then speak_espeak(text, voice: voice.to_s, play: play)
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
