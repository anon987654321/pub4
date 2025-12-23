#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# SOS DILLA v2.1.0 - Cross-Platform Lo-Fi Production System
# =============================================================================
# Targets: Cygwin (Windows 11), OpenBSD VPS, Android Termux (Samsung)
# Backend: FFmpeg (universal) - replaces SoX for cross-platform compatibility
# =============================================================================
# Sources:
#   - J Dilla: Fantastic Vol 1 & 2, Donuts, The Shining, unreleased
#   - Flying Lotus: Los Angeles (2008)
#   - Madlib: Madvillainy, Beat Konducta
#   - Sonitex STX-1260, NastyVCS mkII, Moog DFAM
#   - arXiv papers on tape/vinyl emulation
#   - Bahadırhan Koçer: "Understanding Dub Drums" (dub techno)
# =============================================================================

require "json"
require "fileutils"
require "tempfile"
require "securerandom"

class SOSDilla
  VERSION = "2.1.0"
  CONFIG_FILE = File.join(File.dirname(__FILE__), "dilla_config.json")
  
  # Load shared config
  def self.load_config
    if File.exist?(CONFIG_FILE)
      JSON.parse(File.read(CONFIG_FILE))
    else
      puts "⚠️  Config not found at #{CONFIG_FILE}, using defaults"
      {}
    end
  rescue JSON::ParserError => e
    puts "⚠️  Config parse error: #{e.message}"
    {}
  end
  
  CONFIG = load_config

  # ===========================================================================
  # CHORD PROGRESSIONS (from shared config)
  # ===========================================================================
  def self.get_chords(artist, album, track = nil)
    chords = CONFIG.dig("chords", "#{artist}_#{album}")
    return chords[track] if track && chords&.dig(track)
    chords
  end
  
  DILLA_CHORDS = CONFIG.dig("chords") || {}
  
  # ===========================================================================
  # TIMING PROFILES (from shared config)
  # ===========================================================================
  DILLA_TIMING = CONFIG.dig("timing", "dilla_swing") || {
    "sweet_spot" => [53, 56],
    "tempo_range" => [82, 92],
    "nudge_ms" => { "kick" => -8, "snare" => 12, "hihat" => -3 }
  }

  # ===========================================================================
  # PLATFORM DETECTION
  # ===========================================================================
  module Platform
    def self.detect
      @platform ||= begin
        if ENV['PREFIX']&.include?('com.termux')
          :termux
        elsif RUBY_PLATFORM =~ /cygwin/i
          :cygwin
        elsif RUBY_PLATFORM =~ /openbsd/i
          :openbsd
        elsif RUBY_PLATFORM =~ /darwin/i
          :macos
        elsif RUBY_PLATFORM =~ /linux/i
          :linux
        elsif RUBY_PLATFORM =~ /mingw|mswin/i
          :windows
        else
          :unknown
        end
      end
    end

    def self.termux?;  detect == :termux  end
    def self.cygwin?;  detect == :cygwin  end
    def self.openbsd?; detect == :openbsd end

    def self.home
      ENV['HOME'] || case detect
        when :termux then '/data/data/com.termux/files/home'
        when :cygwin then '/home/' + ENV['USER'].to_s
        else Dir.pwd
      end
    end

    def self.ffmpeg_paths
      case detect
      when :termux
        %w[ffmpeg /data/data/com.termux/files/usr/bin/ffmpeg]
      when :cygwin
        %w[ffmpeg /usr/bin/ffmpeg /cygdrive/c/ffmpeg/bin/ffmpeg.exe]
      when :openbsd
        %w[ffmpeg /usr/local/bin/ffmpeg]
      else
        %w[ffmpeg /usr/bin/ffmpeg /usr/local/bin/ffmpeg]
      end
    end

    def self.install_hint
      case detect
      when :termux  then "pkg install ffmpeg ruby"
      when :cygwin  then "apt-cyg install ffmpeg ruby"
      when :openbsd then "pkg_add ffmpeg ruby"
      when :macos   then "brew install ffmpeg"
      else "Install ffmpeg from https://ffmpeg.org"
      end
    end
  end

  # ===========================================================================
  # DUB PROGRESSIONS (from transcript: i-v tension, i-iv meditative)
  # ===========================================================================
  DUB_PROGRESSIONS = {
    "dub_meditative" => [
      { root: 0, chord: [0, 3, 7], name: "min", function: "i" },
      { root: 5, chord: [0, 3, 7], name: "min", function: "iv" }
    ],
    "dub_tension" => [
      { root: 0, chord: [0, 3, 7], name: "min", function: "i" },
      { root: 7, chord: [0, 3, 7], name: "min", function: "v" }
    ],
    "rhythm_and_sound" => [
      { root: 0, chord: [0, 3, 7, 10], name: "min7", function: "i" },
      { root: 5, chord: [0, 3, 7, 10], name: "min7", function: "iv" }
    ],
    "basic_channel" => [
      { root: 0, chord: [0, 3, 7, 10], name: "min7", function: "i" }
    ]
  }

  # ===========================================================================
  # DUB DRUM PATTERNS (from transcript)
  # ===========================================================================
  DUB_PATTERNS = {
    one_drop: {
      name: "One-Drop",
      desc: "Strong hit on beat 3, reggae foundation",
      kick:    [0, 0, 1, 0],
      snare:   [0, 0, 1, 0],
      hihat:   [1, 1, 1, 1],
      rimshot: [0, 0, 1, 0]
    },
    steppers: {
      name: "Steppers",
      desc: "Four-on-the-floor mechanized groove",
      kick:    [1, 1, 1, 1],
      snare:   [0, 0, 1, 0],
      hihat:   [1, 1, 1, 1],
      rimshot: [0, 1, 0, 1]
    },
    rockers: {
      name: "Rockers",
      desc: "Syncopated driving rhythm",
      kick:    [1, 0, 0, 1],
      snare:   [0, 1, 0, 1],
      hihat:   [1, 1, 1, 1],
      rimshot: [0, 0, 1, 0]
    },
    atmospheric: {
      name: "Atmospheric",
      desc: "Berlin minimal, mechanized precision",
      kick:    [1, 0, 1, 0],
      snare:   [0, 0, 0, 0],
      hihat:   [1, 1, 1, 1],
      rimshot: [0, 0, 1, 0]
    }
  }

  # ===========================================================================
  # TIMING PROFILES
  # ===========================================================================
  DUB_TIMING = {
    mechanized: { swing: 0.50, humanize_ms: 2,  desc: "Germanic precision" },
    roots:      { swing: 0.54, humanize_ms: 25, desc: "Laid back, behind beat" },
    hybrid:     { swing: 0.52, humanize_ms: 8,  desc: "Precision with soul" }
  }

  DILLA_TIMING = {
    swing: 0.542,
    micro: { kick: -0.008, snare: 0.012, hats: -0.003, bass: -0.005 },
    humanize: { velocity: 15, timing: 0.018 }
  }

  # ===========================================================================
  # DELAY PRESETS (from transcript)
  # ===========================================================================
  DUB_DELAYS = {
    echo_16th:    { time_ms: 125, feedback: 0.45 },
    echo_8th_dot: { time_ms: 375, feedback: 0.55 },
    rimshot:      { time_ms: 380, feedback: 0.50 },
    midside:      { time_ms: 188, feedback: 0.45 }
  }

  # ===========================================================================
  # VINTAGE EQUIPMENT PROFILES
  # ===========================================================================
  VINTAGE = {
    king_tubby:      { reverb: 3.2, echo: 0.6, desc: "King Tubby Jamaica 1970s" },
    basic_channel:   { reverb: 6.0, echo: 0.55, desc: "Berlin minimal meets dub" },
    rhythm_and_sound:{ reverb: 4.5, echo: 0.58, desc: "Warmth with precision" },
    wackie:          { reverb: 2.8, echo: 0.50, desc: "South Bronx grit" },
    mpc3000:         { bits: 14, sat: 0.12, desc: "J Dilla MPC character" },
    sp1200:          { bits: 12, sat: 0.15, desc: "E-mu SP-1200 grit" }
  }

  # ===========================================================================
  # FFMPEG PROCESSOR
  # ===========================================================================
  class FFmpegProcessor
    attr_reader :sample_rate

    def initialize(sample_rate: 48000)
      @sample_rate = sample_rate
      @ffmpeg = find_ffmpeg
    end

    def find_ffmpeg
      Platform.ffmpeg_paths.find { |p| system("#{p} -version >/dev/null 2>&1") } || 'ffmpeg'
    end

    def available?
      system("#{@ffmpeg} -version >/dev/null 2>&1")
    end

    def run(cmd)
      system(cmd + " >/dev/null 2>&1")
    end

    def tone(freq:, duration:, wave: :sine, output:, amp: 0.8)
      w = { sine: 'sine', square: 'square', triangle: 'triangle', sawtooth: 'sawtooth' }[wave] || 'sine'
      run(%Q[#{@ffmpeg} -y -f lavfi -i "#{w}=f=#{freq}:d=#{duration}:r=#{@sample_rate}" -af "volume=#{amp}" "#{output}"])
    end

    def noise(duration:, output:, color: :white, amp: 0.5)
      c = { white: 'white', pink: 'pink', brown: 'brown' }[color] || 'white'
      run(%Q[#{@ffmpeg} -y -f lavfi -i "anoisesrc=d=#{duration}:c=#{c}noise:r=#{@sample_rate}" -af "volume=#{amp}" "#{output}"])
    end

    def filter(input:, output:, chain:)
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "#{chain}" "#{output}"])
    end

    def echo(input:, output:, delay_ms: 300, feedback: 0.5, mix: 0.5)
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "aecho=0.8:#{mix}:#{delay_ms}:#{feedback}" "#{output}"])
    end

    def reverb(input:, output:, decay: 0.5, size: :medium)
      delays = { small: "50|100", medium: "60|120|180", large: "80|160|240|320", spring: "30|45|60" }[size] || "60|120"
      decays = delays.split('|').map { decay.to_s }.join('|')
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "aecho=0.8:0.7:#{delays}:#{decays}" "#{output}"])
    end

    def eq(input:, output:, bands:)
      f = bands.map { |b| "equalizer=f=#{b[:freq]}:width_type=q:width=#{b[:q]||1}:g=#{b[:gain]}" }.join(',')
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "#{f}" "#{output}"])
    end

    def lowpass(input:, output:, cutoff:)
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "lowpass=f=#{cutoff}" "#{output}"])
    end

    def highpass(input:, output:, cutoff:)
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "highpass=f=#{cutoff}" "#{output}"])
    end

    def compress(input:, output:, threshold: -20, ratio: 4)
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "acompressor=threshold=#{threshold}dB:ratio=#{ratio}" "#{output}"])
    end

    def saturate(input:, output:, drive: 2.0)
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "volume=#{drive},atanh,volume=#{1.0/drive}" "#{output}"])
    end

    def bitcrush(input:, output:, bits: 12)
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "acrusher=bits=#{bits}:mode=lin" "#{output}"])
    end

    def mix(inputs:, output:, volumes: nil)
      volumes ||= inputs.map { 1.0 }
      args = inputs.map { |f| %Q[-i "#{f}"] }.join(' ')
      vol = inputs.each_with_index.map { |_,i| "[#{i}]volume=#{volumes[i]}[v#{i}]" }.join(';')
      ins = inputs.each_with_index.map { |_,i| "[v#{i}]" }.join
      run(%Q[#{@ffmpeg} -y #{args} -filter_complex "#{vol};#{ins}amix=inputs=#{inputs.length}:duration=longest" "#{output}"])
    end

    def normalize(input:, output:, target: -1)
      run(%Q[#{@ffmpeg} -y -i "#{input}" -af "loudnorm=I=-16:TP=#{target}" "#{output}"])
    end
  end

  # ===========================================================================
  # MAIN CLASS
  # ===========================================================================
  attr_reader :ffmpeg, :temp_dir, :output_dir

  def initialize
    @temp_dir = Dir.mktmpdir("dilla_")
    @output_dir = File.join(Platform.home, "dilla_output")
    FileUtils.mkdir_p(@output_dir)
    @ffmpeg = FFmpegProcessor.new
    check_deps
  end

  def check_deps
    unless @ffmpeg.available?
      puts "❌ FFmpeg not found! Install: #{Platform.install_hint}"
      exit 1
    end
    puts "✓ FFmpeg ready on #{Platform.detect}"
  end

  def generate_dub(pattern: :one_drop, progression: "dub_meditative", key: "E", bpm: 120, bars: 4)
    puts "🎚️  Generating: #{pattern} | #{progression} | #{key} | #{bpm}BPM"
    
    pat = DUB_PATTERNS[pattern]
    duration = (60.0 / bpm) * 4 * bars
    base_freq = note_freq(key, 2)

    # Generate layers
    drums = temp("drums.wav")
    bass = temp("bass.wav")
    chords = temp("chords.wav")

    # Drums: kick + noise
    kick = temp("kick.wav")
    @ffmpeg.tone(freq: 55, duration: 0.3, wave: :sine, output: kick, amp: 0.9)
    @ffmpeg.lowpass(input: kick, output: kick, cutoff: 120)

    hat = temp("hat.wav")
    @ffmpeg.noise(duration: 0.05, output: hat, amp: 0.15)
    @ffmpeg.highpass(input: hat, output: hat, cutoff: 8000)

    silence = temp("silence.wav")
    @ffmpeg.tone(freq: 1, duration: duration, wave: :sine, output: silence, amp: 0)
    @ffmpeg.mix(inputs: [silence, kick, hat], output: drums, volumes: [1, 0.8, 0.3])

    # Bass
    @ffmpeg.tone(freq: base_freq, duration: duration, wave: :sine, output: bass, amp: 0.7)
    @ffmpeg.lowpass(input: bass, output: bass, cutoff: 200)

    # Chords  
    @ffmpeg.tone(freq: base_freq * 4, duration: duration, wave: :triangle, output: chords, amp: 0.25)

    # Process with dub FX
    drums_fx = temp("drums_fx.wav")
    @ffmpeg.reverb(input: drums, output: drums_fx, decay: 0.4, size: :spring)
    @ffmpeg.echo(input: drums_fx, output: drums_fx, delay_ms: 375, feedback: 0.35)

    bass_fx = temp("bass_fx.wav")
    @ffmpeg.compress(input: bass, output: bass_fx, threshold: -15, ratio: 4)

    chords_fx = temp("chords_fx.wav")
    @ffmpeg.echo(input: chords, output: chords_fx, delay_ms: 125, feedback: 0.4)
    @ffmpeg.reverb(input: chords_fx, output: chords_fx, decay: 0.5, size: :large)

    # Mix
    mixed = temp("mixed.wav")
    @ffmpeg.mix(inputs: [drums_fx, bass_fx, chords_fx], output: mixed, volumes: [1.0, 0.8, 0.5])

    # Master
    final = File.join(@output_dir, "dub_#{pattern}_#{key}_#{bpm}_#{timestamp}.wav")
    master_out = temp("master.wav")
    @ffmpeg.eq(input: mixed, output: master_out, bands: [
      { freq: 60, gain: 2, q: 0.7 },
      { freq: 3000, gain: -1, q: 1.5 }
    ])
    @ffmpeg.normalize(input: master_out, output: final)

    puts "✓ Generated: #{final}"
    final
  end

  def generate_dilla(style: "donuts", key: "C", bpm: 95)
    puts "🎹 Generating Dilla: #{style} | #{key} | #{bpm}BPM"
    
    duration = 8.0
    base_freq = note_freq(key, 3)

    raw = temp("raw.wav")
    @ffmpeg.tone(freq: base_freq, duration: duration, wave: :triangle, output: raw, amp: 0.5)

    crushed = temp("crushed.wav")
    @ffmpeg.bitcrush(input: raw, output: crushed, bits: 14)

    warm = temp("warm.wav")
    @ffmpeg.saturate(input: crushed, output: warm, drive: 1.8)

    eq_out = temp("eq.wav")
    @ffmpeg.eq(input: warm, output: eq_out, bands: [
      { freq: 100, gain: 3, q: 0.8 },
      { freq: 8000, gain: -2.5, q: 1.2 }
    ])

    final = File.join(@output_dir, "dilla_#{style}_#{key}_#{bpm}_#{timestamp}.wav")
    @ffmpeg.compress(input: eq_out, output: final, threshold: -20, ratio: 4)

    puts "✓ Generated: #{final}"
    final
  end

  def master(input:, era: :rhythm_and_sound)
    puts "🎨 Mastering: #{era}"
    v = VINTAGE[era] || VINTAGE[:rhythm_and_sound]
    puts "   #{v[:desc]}"

    processed = temp("master.wav")
    
    if v[:bits]
      @ffmpeg.bitcrush(input: input, output: processed, bits: v[:bits])
      @ffmpeg.saturate(input: processed, output: processed, drive: 1.5)
    else
      @ffmpeg.reverb(input: input, output: processed, decay: v[:reverb]/10.0, size: :medium)
      @ffmpeg.echo(input: processed, output: processed, delay_ms: 280, feedback: v[:echo])
    end

    final = File.join(@output_dir, "master_#{era}_#{timestamp}.wav")
    @ffmpeg.normalize(input: processed, output: final)

    puts "✓ Mastered: #{final}"
    final
  end

  def export_config
    {
      version: VERSION,
      platform: Platform.detect,
      patterns: DUB_PATTERNS.transform_values { |p| { name: p[:name], desc: p[:desc] } },
      progressions: DUB_PROGRESSIONS.keys,
      delays: DUB_DELAYS,
      vintage: VINTAGE.transform_values { |v| v[:desc] }
    }.to_json
  end

  def note_freq(note, octave = 4)
    semitones = { "C"=>0,"C#"=>1,"D"=>2,"D#"=>3,"E"=>4,"F"=>5,"F#"=>6,"G"=>7,"G#"=>8,"A"=>9,"A#"=>10,"B"=>11 }
    440.0 * (2.0 ** ((semitones[note].to_i - 9 + (octave - 4) * 12) / 12.0))
  end

  def temp(name); File.join(@temp_dir, name) end
  def timestamp; Time.now.strftime("%Y%m%d_%H%M%S") end
  def cleanup; FileUtils.rm_rf(@temp_dir) end

  # ===========================================================================
  # GEAR EMULATION - Vintage Sampler Character
  # ===========================================================================
  GEAR_PROFILES = {
    sp1200: {
      name: "E-mu SP-1200",
      bits: 12, sample_rate: 26040, filter_hz: 12000,
      saturation: 1.8, character: "punchy_gritty"
    },
    mpc3000: {
      name: "Akai MPC3000", 
      bits: 16, sample_rate: 44100, filter_hz: 18000,
      saturation: 1.2, character: "warm_precise"
    },
    mpc60: {
      name: "Akai MPC60",
      bits: 12, sample_rate: 40000, filter_hz: 14000,
      saturation: 1.5, character: "fat_punchy"
    },
    sp303: {
      name: "Boss SP-303",
      bits: 16, sample_rate: 22050, filter_hz: 10000,
      saturation: 1.3, vinyl_sim: true, character: "lofi_cassette_warm"
    },
    sp404: {
      name: "Roland SP-404",
      bits: 16, sample_rate: 44100, filter_hz: 16000,
      saturation: 1.1, character: "harsh_brittle"
    },
    s950: {
      name: "Akai S950",
      bits: 12, sample_rate: 48000, filter_hz: 14000,
      saturation: 1.4, analog_filter: true, character: "warm_classic"
    },
    s900: {
      name: "Akai S900",
      bits: 12, sample_rate: 40000, filter_hz: 12000,
      saturation: 1.6, character: "gritty_raw"
    },
    emax: {
      name: "E-mu Emax",
      bits: 12, sample_rate: 28000, filter_hz: 10000,
      saturation: 1.7, ssm_filter: true, character: "gritty_sp1200_cousin"
    },
    mirage: {
      name: "Ensoniq Mirage",
      bits: 8, sample_rate: 30000, filter_hz: 8000,
      saturation: 2.0, analog_vcf: true, character: "extremely_lofi_harsh"
    }
  }

  # ===========================================================================
  # RANDOM EFFECT CHAIN GENERATOR
  # ===========================================================================
  module ChainGenerator
    EFFECTS = {
      bitcrush:     { bits: [8, 10, 12, 14], weight: 0.8 },
      resample:     { rates: [8000, 11025, 22050, 26040, 32000], weight: 0.6 },
      lowpass:      { cutoff: [2000, 4000, 8000, 12000, 16000], weight: 0.9 },
      highpass:     { cutoff: [20, 40, 80, 150, 300], weight: 0.5 },
      saturation:   { drive: [1.2, 1.5, 1.8, 2.2, 2.8], weight: 0.85 },
      tape_sat:     { drive: [1.1, 1.3, 1.5, 1.8], weight: 0.7 },
      transformer:  { amount: [0.1, 0.2, 0.3, 0.4], weight: 0.5 },
      tube_sat:     { drive: [1.1, 1.3, 1.6, 2.0], weight: 0.6 },
      vinyl_noise:  { amount: [0.05, 0.1, 0.15, 0.25], weight: 0.7 },
      tape_hiss:    { amount: [0.03, 0.08, 0.12, 0.18], weight: 0.5 },
      wow_flutter:  { rate: [0.2, 0.4, 0.7, 1.0], depth: [0.01, 0.02, 0.03], weight: 0.4 },
      compression:  { ratio: [2, 3, 4, 6, 8], threshold: [-24, -18, -12], weight: 0.75 },
      reverb:       { size: [0.1, 0.2, 0.3, 0.4], decay: [0.3, 0.5, 0.8], weight: 0.3 },
      delay:        { time_ms: [80, 125, 180, 250], feedback: [0.2, 0.35, 0.5], weight: 0.3 },
      chorus:       { rate: [0.5, 1.2, 2.5], depth: [0.2, 0.35, 0.5], weight: 0.2 },
      phaser:       { rate: [0.3, 0.7, 1.5], weight: 0.15 },
      tremolo:      { rate: [2, 4, 6, 8], depth: [0.3, 0.5, 0.7], weight: 0.2 },
      ring_mod:     { freq: [200, 500, 1000, 2000], weight: 0.08 }
    }

    AESTHETICS = {
      dark:      { lowpass: 0.95, saturation: 0.8, reverb: 0.4, bitcrush: 0.3 },
      deep:      { lowpass: 0.95, compression: 0.9, saturation: 0.7, highpass: 0.2 },
      authentic: { bitcrush: 0.9, vinyl_noise: 0.8, tape_sat: 0.7, lowpass: 0.6 },
      tape:      { tape_sat: 0.95, wow_flutter: 0.85, tape_hiss: 0.7, saturation: 0.5 },
      vinyl:     { vinyl_noise: 0.95, lowpass: 0.7, saturation: 0.5, wow_flutter: 0.4 },
      gritty:    { bitcrush: 0.9, saturation: 0.95, resample: 0.7, lowpass: 0.5 },
      cosmic:    { reverb: 0.8, delay: 0.7, chorus: 0.5, phaser: 0.4, lowpass: 0.6 },
      industrial:{ ring_mod: 0.4, saturation: 0.9, bitcrush: 0.7, compression: 0.8 }
    }

    def self.generate(aesthetic: :authentic, length: nil, seed: nil)
      srand(seed) if seed
      prng = Random.new(seed || Random.new_seed)
      
      weights = AESTHETICS[aesthetic] || AESTHETICS[:authentic]
      chain_length = length || prng.rand(3..7)
      
      chain = []
      used = Set.new
      
      chain_length.times do
        candidates = EFFECTS.keys.reject { |e| used.include?(e) }
        break if candidates.empty?
        
        # Weight selection by aesthetic
        weighted = candidates.map do |effect|
          base_weight = EFFECTS[effect][:weight]
          aesthetic_boost = weights[effect] || 0
          [effect, base_weight + aesthetic_boost]
        end
        
        total = weighted.sum { |_, w| w }
        roll = prng.rand * total
        
        selected = nil
        cumulative = 0
        weighted.each do |effect, weight|
          cumulative += weight
          if roll <= cumulative
            selected = effect
            break
          end
        end
        selected ||= candidates.sample(random: prng)
        
        effect_params = EFFECTS[selected].dup
        effect_params.delete(:weight)
        
        # Randomize parameters
        params = { type: selected }
        effect_params.each do |param, values|
          params[param] = values.is_a?(Array) ? values.sample(random: prng) : values
        end
        
        chain << params
        used << selected
      end
      
      chain
    end

    def self.to_s(chain)
      chain.map { |e| "#{e[:type]}(#{e.except(:type).map { |k,v| "#{k}:#{v}" }.join(',')})" }.join(" → ")
    end
  end

  # ===========================================================================
  # DFAM-STYLE ANALOG PERCUSSION SYNTHESIS
  # ===========================================================================
  module DFAM
    PRESETS = {
      tribal_kick: {
        osc1: { wave: :sine, freq: 55, decay: 0.3 },
        osc2: { wave: :sine, freq: 110, decay: 0.15 },
        noise: 0.05, filter_env: 0.8, filter_decay: 0.2
      },
      industrial_hit: {
        osc1: { wave: :square, freq: 80, decay: 0.1 },
        osc2: { wave: :saw, freq: 160, decay: 0.08 },
        noise: 0.3, filter_env: 0.9, filter_decay: 0.15, fm: 0.4
      },
      metallic_tom: {
        osc1: { wave: :triangle, freq: 200, decay: 0.25 },
        osc2: { wave: :sine, freq: 350, decay: 0.2 },
        noise: 0.1, filter_env: 0.5, filter_decay: 0.3
      },
      noise_snare: {
        osc1: { wave: :triangle, freq: 180, decay: 0.08 },
        osc2: { wave: :square, freq: 220, decay: 0.05 },
        noise: 0.7, filter_env: 0.6, filter_decay: 0.12
      },
      drone_bass: {
        osc1: { wave: :saw, freq: 40, decay: 2.0 },
        osc2: { wave: :square, freq: 41, decay: 2.0 },
        noise: 0.02, filter_env: 0.3, filter_decay: 1.5
      }
    }
  end

  # ===========================================================================
  # SONITEX STX-1260 STYLE PROCESSING
  # ===========================================================================
  module Sonitex
    def self.process(ffmpeg, input:, output:, preset: :vintage_vinyl)
      presets = {
        vintage_vinyl: {
          distortion: { type: :saturation, drive: 1.3 },
          vinyl: { warble: 0.02, sibilance: 0.4 },
          tone: { lowpass: 12000, highpass: 40 },
          noise: { type: :vinyl, pops: 0.1, clicks: 0.05, base: 0.08 },
          sampling: { bits: 14, rate: 32000 }
        },
        tape_machine: {
          distortion: { type: :tape, drive: 1.5 },
          vinyl: { warble: 0.03, sibilance: 0.2 },
          tone: { lowpass: 14000, highpass: 30 },
          noise: { type: :tape_hiss, amount: 0.12 },
          sampling: { bits: 16, rate: 44100 }
        },
        sp1200_crunch: {
          distortion: { type: :digital1, drive: 1.8 },
          vinyl: { warble: 0, sibilance: 0 },
          tone: { lowpass: 10000, highpass: 60 },
          noise: { type: :none },
          sampling: { bits: 12, rate: 26040 }
        },
        extreme_lofi: {
          distortion: { type: :distortion, drive: 2.5 },
          vinyl: { warble: 0.05, sibilance: 0.6 },
          tone: { lowpass: 4000, highpass: 200 },
          noise: { type: :vinyl, pops: 0.3, clicks: 0.2, base: 0.25 },
          sampling: { bits: 8, rate: 11025 }
        }
      }
      
      cfg = presets[preset] || presets[:vintage_vinyl]
      
      # Apply chain: distortion → tone → sampling → noise
      temp1 = output.sub('.wav', '_s1.wav')
      ffmpeg.saturate(input: input, output: temp1, drive: cfg[:distortion][:drive])
      
      temp2 = output.sub('.wav', '_s2.wav')
      ffmpeg.lowpass(input: temp1, output: temp2, cutoff: cfg[:tone][:lowpass])
      
      if cfg[:sampling][:bits] < 16
        temp3 = output.sub('.wav', '_s3.wav')
        ffmpeg.bitcrush(input: temp2, output: temp3, bits: cfg[:sampling][:bits])
        ffmpeg.resample(input: temp3, output: output, rate: cfg[:sampling][:rate])
      else
        FileUtils.cp(temp2, output)
      end
      
      # Cleanup
      [temp1, temp2].each { |f| File.delete(f) if File.exist?(f) }
    end
  end

  # ===========================================================================
  # NASTYVCS-STYLE CONSOLE PROCESSING  
  # ===========================================================================
  module NastyVCS
    def self.process(ffmpeg, input:, output:, settings: {})
      cfg = {
        input_transformer: true,
        saturation: 0.3,
        eq_air_db: 1.5,
        eq_low_db: 2.0,
        compression_ratio: 3,
        compression_attack: :medium,
        output_transformer: true
      }.merge(settings)
      
      temp = output.sub('.wav', '_nvcs.wav')
      
      # Transformer saturation
      ffmpeg.saturate(input: input, output: temp, drive: 1.0 + cfg[:saturation])
      
      # EQ with console character
      ffmpeg.eq(input: temp, output: output, bands: [
        { freq: 80, gain: cfg[:eq_low_db], q: 0.8 },
        { freq: 12000, gain: cfg[:eq_air_db], q: 0.7 }
      ])
      
      File.delete(temp) if File.exist?(temp)
    end
  end

  # ===========================================================================
  # APPLY GEAR EMULATION
  # ===========================================================================
  def apply_gear(input:, output:, gear: :sp1200)
    profile = GEAR_PROFILES[gear] || GEAR_PROFILES[:sp1200]
    puts "🎛️  Applying #{profile[:name]} character..."
    
    temp1 = temp("gear1.wav")
    temp2 = temp("gear2.wav")
    
    # Resample to gear's native rate
    @ffmpeg.resample(input: input, output: temp1, rate: profile[:sample_rate])
    
    # Bitcrush
    @ffmpeg.bitcrush(input: temp1, output: temp2, bits: profile[:bits])
    
    # Filter
    temp3 = temp("gear3.wav")
    @ffmpeg.lowpass(input: temp2, output: temp3, cutoff: profile[:filter_hz])
    
    # Saturation
    @ffmpeg.saturate(input: temp3, output: output, drive: profile[:saturation])
    
    puts "   Character: #{profile[:character]}"
    output
  end

  # ===========================================================================
  # GENERATE RANDOM LO-FI CHAIN
  # ===========================================================================
  def generate_random_chain(input:, aesthetic: :authentic, seed: nil)
    chain = ChainGenerator.generate(aesthetic: aesthetic, seed: seed)
    puts "🎲 Random chain (#{aesthetic}): #{ChainGenerator.to_s(chain)}"
    
    current = input
    chain.each_with_index do |effect, i|
      next_file = temp("chain_#{i}.wav")
      
      case effect[:type]
      when :bitcrush
        @ffmpeg.bitcrush(input: current, output: next_file, bits: effect[:bits])
      when :resample
        @ffmpeg.resample(input: current, output: next_file, rate: effect[:rates])
      when :lowpass
        @ffmpeg.lowpass(input: current, output: next_file, cutoff: effect[:cutoff])
      when :highpass
        @ffmpeg.highpass(input: current, output: next_file, cutoff: effect[:cutoff])
      when :saturation, :tape_sat, :tube_sat, :transformer
        @ffmpeg.saturate(input: current, output: next_file, drive: effect[:drive] || (1.0 + (effect[:amount] || 0.3)))
      when :compression
        @ffmpeg.compress(input: current, output: next_file, threshold: effect[:threshold], ratio: effect[:ratio])
      when :reverb
        @ffmpeg.reverb(input: current, output: next_file, decay: effect[:decay], size: :medium)
      when :delay
        @ffmpeg.echo(input: current, output: next_file, delay_ms: effect[:time_ms], feedback: effect[:feedback])
      when :tremolo
        @ffmpeg.tremolo(input: current, output: next_file, rate: effect[:rate], depth: effect[:depth])
      else
        FileUtils.cp(current, next_file)
      end
      
      current = next_file
    end
    
    final = File.join(@output_dir, "random_#{aesthetic}_#{SecureRandom.hex(4)}_#{timestamp}.wav")
    @ffmpeg.normalize(input: current, output: final)
    
    puts "✓ Generated: #{final}"
    { file: final, chain: chain }
  end

  # ===========================================================================
  # CLI
  # ===========================================================================
  def self.main(args)
    return show_help if args.empty? || args.include?("--help")

    dilla = new
    begin
      case args[0]
      when "dub"
        dilla.generate_dub(
          pattern: (args[1] || "one_drop").to_sym,
          progression: args[2] || "dub_meditative",
          key: args[3] || "E",
          bpm: (args[4] || "120").to_i
        )
      when "dilla"
        dilla.generate_dilla(style: args[1] || "donuts", key: args[2] || "C", bpm: (args[3] || "95").to_i)
      when "random"
        aesthetic = (args[1] || "authentic").to_sym
        seed = args[2] ? args[2].to_i : nil
        # Generate a test tone first, then process
        test = dilla.send(:temp, "test_tone.wav")
        dilla.instance_variable_get(:@ffmpeg).tone(output: test, freq: 440, duration: 4)
        dilla.generate_random_chain(input: test, aesthetic: aesthetic, seed: seed)
      when "gear"
        gear = (args[1] || "sp1200").to_sym
        input = args[2]
        if input && File.exist?(input)
          output = File.join(dilla.instance_variable_get(:@output_dir), "#{gear}_#{dilla.send(:timestamp)}.wav")
          dilla.apply_gear(input: input, output: output, gear: gear)
        else
          puts "Usage: dilla.rb gear <sp1200|mpc3000|sp303|s950|...> <input.wav>"
        end
      when "master"
        dilla.master(input: args[1], era: (args[2] || "rhythm_and_sound").to_sym) if args[1] && File.exist?(args[1])
      when "config"
        puts dilla.export_config
      when "chords"
        artist = args[1] || "dilla"
        album = args[2] || "fantastic_vol2"
        chords = SOSDilla.get_chords(artist, album)
        if chords
          puts JSON.pretty_generate(chords)
        else
          puts "Available: dilla_fantastic_vol1, dilla_fantastic_vol2, dilla_donuts, flying_lotus_la, madlib"
        end
      when "list"
        puts "\nPATTERNS: #{DUB_PATTERNS.keys.join(', ')}"
        puts "PROGRESSIONS: #{DUB_PROGRESSIONS.keys.join(', ')}"
        puts "ERAS: #{VINTAGE.keys.join(', ')}"
        puts "GEAR: #{GEAR_PROFILES.keys.join(', ')}"
        puts "AESTHETICS: #{ChainGenerator::AESTHETICS.keys.join(', ')}"
      else
        show_help
      end
    ensure
      dilla.cleanup
    end
  end

  def self.show_help
    puts <<~HELP
      SOS Dilla v#{VERSION} | #{Platform.detect}

      USAGE:
        dilla.rb dub [pattern] [prog] [key] [bpm]    Generate dub techno
        dilla.rb dilla [style] [key] [bpm]           Generate Dilla-style beat
        dilla.rb random [aesthetic] [seed]           Random lo-fi effect chain
        dilla.rb gear <type> <input.wav>             Apply vintage sampler character
        dilla.rb master <file.wav> [era]             Master with vintage color
        dilla.rb chords [artist] [album]             Show chord progressions
        dilla.rb list                                List all options
        dilla.rb config                              Export JSON config

      PATTERNS: one_drop, steppers, rockers, atmospheric
      GEAR: #{GEAR_PROFILES.keys.join(', ')}
      AESTHETICS: dark, deep, authentic, tape, vinyl, gritty, cosmic, industrial
      ERAS: king_tubby, basic_channel, rhythm_and_sound, wackie, mpc3000, sp1200

      INSTALL: #{Platform.install_hint}
    HELP
  end
end

SOSDilla.main(ARGV) if __FILE__ == $PROGRAM_NAME
