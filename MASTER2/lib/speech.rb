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
    extend self
    extend Backends
    extend Playback
    extend Streaming
    extend Utils

    ZERO_RATE = "+0%".freeze
    ZERO_PITCH = "+0Hz".freeze

    # Engine selection priority
    ENGINES = %i[piper edge replicate].freeze

    # FFmpeg effect presets for streaming
    STREAM_EFFECTS = {
      dark: "asetrate=44100*0.8,atempo=1.25,bass=g=10",
      demon: "asetrate=44100*0.7,atempo=1.4,bass=g=15,acompressor=threshold=0.08:ratio=12",
      robot: "asetrate=44100*0.9,atempo=1.1,flanger,tremolo=f=10:d=0.5",
      radio: "highpass=f=300,lowpass=f=3000,acompressor=threshold=0.1:ratio=8",
      underwater: "asetrate=44100*0.6,atempo=1.6,lowpass=f=800,chorus=0.5:0.9:50:0.4:0.25:2",
      ghost: "asetrate=44100*0.75,atempo=1.33,areverse,aecho=0.8:0.88:60:0.4,areverse",
    }.freeze

    # Voice styles (rate/pitch adjustments for Edge)
    STYLES = {
      normal: { rate: ZERO_RATE, pitch: ZERO_PITCH }.freeze,
      fast: { rate: "+25%", pitch: ZERO_PITCH }.freeze,
      slow: { rate: "-20%", pitch: ZERO_PITCH }.freeze,
      high: { rate: ZERO_RATE, pitch: "+50Hz" }.freeze,
      low: { rate: ZERO_RATE, pitch: "-50Hz" }.freeze,
      excited: { rate: "+15%", pitch: "+30Hz" }.freeze,
      calm: { rate: "-10%", pitch: "-20Hz" }.freeze,
      whisper: { rate: "-15%", pitch: "-30Hz" }.freeze,
      urgent: { rate: "+30%", pitch: "+20Hz" }.freeze,
    }.freeze

    # Piper voice presets (length_scale/noise_scale)
    PIPER_PRESETS = {
      normal: { length_scale: 1.0, noise_scale: 0.667 }.freeze,
      chipmunk: { length_scale: 0.6, noise_scale: 0.667 }.freeze,
      zombie: { length_scale: 2.5, noise_scale: 0.4 }.freeze,
      robot: { length_scale: 1.0, noise_scale: 0.1 }.freeze,
      manic: { length_scale: 0.8, noise_scale: 0.9 }.freeze,
      calm: { length_scale: 1.2, noise_scale: 0.3 }.freeze,
      urgent: { length_scale: 0.7, noise_scale: 0.5 }.freeze,
      demon: { length_scale: 3.0, noise_scale: 0.3 }.freeze,
      caffeinated: { length_scale: 0.5, noise_scale: 0.7 }.freeze,
    }.freeze

    # Edge TTS voices
    EDGE_VOICES = {
      aria: "en-US-AriaNeural",
      guy: "en-US-GuyNeural",
      jenny: "en-US-JennyNeural",
      davis: "en-US-DavisNeural",
      sonia: "en-GB-SoniaNeural",
      ryan: "en-GB-RyanNeural",
      finn: "nb-NO-FinnNeural",
      pernille: "nb-NO-PernilleNeural",
    }.freeze

    # Speak text using best available engine
    def speak(text, engine: nil, voice: nil, style: :normal, play: true)
      return Result.err("Empty text.") if text.nil? || text.strip.empty?

      engine ||= best_engine
      return Result.err("No TTS engine available.") unless engine

      case engine
      when :piper then speak_piper(text, voice: voice, preset: style, play: play)
      when :edge then speak_edge(text, voice: voice, style: style, play: play)
      when :replicate then speak_replicate(text, play: play)
      else Result.err("Unknown engine: #{engine}")
      end
    end
  end
end
