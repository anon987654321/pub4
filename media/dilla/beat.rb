#!/usr/bin/env ruby
# frozen_string_literal: true

# beat.rb - unified dilla beat maker
# creates all layers: kick, snare, hihat, sample, bass, master
# parses ableton .als files to extract patterns

require "fileutils"
require "json"
require "zlib"
require "rexml/document"

class Beat
  VERSION = "2.1.0"
  SAMPLES_DIR = "/sdcard/music/samples"  # termux path - adjust for your system

  # sample library paths (goldbaby structure)
  KITS = {
    tr808:    { path: "goldbaby/tr_808", kick: "bassdrums/808_bd", snare: "snaredrums/808_sd", hihat: "hihats/808_hh" },
    tr909:    { path: "goldbaby/tr_909", kick: "bassdrums", snare: "snaredrums", hihat: "hihats" },
    linndrum: { path: "goldbaby/linndrum", kick: "linndrum_bd", snare: "linndrum_sd", hihat: "linndrum_hh" },
    cr78:     { path: "goldbaby/cr_78", kick: "bd", snare: "sd", hihat: "hh" },
    dmx:      { path: "goldbaby/custom_dmx", kick: "bd", snare: "sd", hihat: "hh" },
    lm1:      { path: "goldbaby/lm_1", kick: "bd", snare: "sd", hihat: "hh" },
    tr505:    { path: "goldbaby/tr_505", kick: "bd", snare: "sd", hihat: "hh" },
    tr626:    { path: "goldbaby/tr_626", kick: "bd", snare: "sd", hihat: "hh" }
  }

  # timing
  TIMING = {
    swing: 0.542,
    nudge: { kick: -8, snare: 12, hihat: -3, bass: -5 },
    humanize: { velocity: 15, timing: 18 }
  }

  # gear emulation
  GEAR = {
    sp1200:  { bits: 12, rate: 26040, filter: 12000, sat: 1.8 },
    mpc3000: { bits: 16, rate: 44100, filter: 18000, sat: 1.2 },
    mpc60:   { bits: 12, rate: 40000, filter: 14000, sat: 1.5 },
    sp303:   { bits: 16, rate: 22050, filter: 10000, sat: 1.3 },
    s950:    { bits: 12, rate: 48000, filter: 14000, sat: 1.4 },
    s900:    { bits: 12, rate: 40000, filter: 12000, sat: 1.6 }
  }

  # drum patterns (16 steps) - extensive collection
  PATTERNS = {
    # dilla variants
    dilla_lazy: {
      kick:  [1,0,0,0, 0,0,1,0, 0,0,0,0, 0,1,0,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    },
    dilla_bounce: {
      kick:  [1,0,0,1, 0,0,1,0, 0,0,0,1, 0,0,1,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1]
    },
    dilla_donuts: {
      kick:  [1,0,0,0, 0,0,0,1, 0,0,1,0, 0,0,0,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,1],
      hihat: [1,0,1,1, 0,1,1,0, 1,0,1,1, 0,1,1,0]
    },
    dilla_fantastic: {
      kick:  [1,0,0,0, 0,1,0,0, 1,0,0,0, 0,0,1,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,1,0,1, 1,0,1,1, 1,1,0,1, 1,0,1,0]
    },
    # boom bap classics
    boom_bap: {
      kick:  [1,0,0,0, 0,0,0,0, 1,0,1,0, 0,0,0,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    },
    boom_bap_hard: {
      kick:  [1,0,0,0, 0,0,0,0, 0,0,1,0, 0,0,0,0],
      snare: [0,0,0,0, 1,0,0,1, 0,0,0,0, 1,0,0,0],
      hihat: [1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1]
    },
    premier: {
      kick:  [1,0,0,0, 0,0,1,0, 0,1,0,0, 0,0,0,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    },
    pete_rock: {
      kick:  [1,0,0,1, 0,0,0,0, 1,0,0,0, 0,0,1,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    },
    # madlib / stones throw
    madlib: {
      kick:  [1,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    },
    madvillainy: {
      kick:  [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,1,0,1, 1,0,1,1, 1,1,0,1, 1,0,1,0]
    },
    # flylo / brainfeeder
    flylo: {
      kick:  [1,0,0,0, 0,0,0,1, 0,1,0,0, 0,0,1,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,1,0, 1,0,0,1],
      hihat: [1,0,1,1, 0,1,1,0, 1,1,0,1, 1,0,1,0]
    },
    # trap
    trap: {
      kick:  [1,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1]
    },
    trap_roll: {
      kick:  [1,0,0,0, 0,0,1,0, 0,0,0,0, 0,0,1,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1]
    },
    # house / 4x4
    house: {
      kick:  [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
      hihat: [0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0]
    },
    # breakbeat
    breakbeat: {
      kick:  [1,0,0,0, 0,0,1,0, 0,0,0,0, 0,0,0,0],
      snare: [0,0,0,0, 1,0,0,0, 0,0,1,0, 0,0,1,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    },
    amen: {
      kick:  [1,0,0,0, 0,0,1,0, 0,1,0,0, 0,0,0,0],
      snare: [0,0,0,0, 1,0,0,1, 0,0,0,0, 1,0,1,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    },
    # funk
    funk: {
      kick:  [1,0,0,1, 0,0,0,0, 1,0,0,0, 0,1,0,0],
      snare: [0,0,0,0, 1,0,0,1, 0,0,0,0, 1,0,0,0],
      hihat: [1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1]
    },
    # reggae / dub
    one_drop: {
      kick:  [0,0,0,0, 0,0,1,0, 0,0,0,0, 0,0,0,0],
      snare: [0,0,0,0, 0,0,1,0, 0,0,0,0, 0,0,0,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    },
    steppers: {
      kick:  [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0],
      snare: [0,0,0,0, 0,0,1,0, 0,0,0,0, 0,0,1,0],
      hihat: [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
    }
  }

  attr_reader :bpm, :bars, :key, :pattern, :gear, :kit

  def initialize(bpm: 95, bars: 8, key: "C", pattern: :dilla_lazy, gear: :sp303, kit: :tr808)
    @bpm = bpm
    @bars = bars
    @key = key
    @pattern = pattern.is_a?(Hash) ? pattern : (PATTERNS[pattern] || PATTERNS[:dilla_lazy])
    @gear = GEAR[gear] || GEAR[:sp303]
    @kit = KITS[kit] || KITS[:tr808]
    @kit_name = kit
    @beat_ms = (60.0 / bpm * 1000).round
    @bar_ms = @beat_ms * 4
    @duration = bars * @bar_ms / 1000.0
    @sixteenth_ms = @beat_ms / 4.0
    @temp_files = []
  end

  # random beat generator
  def self.random(output: nil)
    pattern = PATTERNS.keys.sample
    kit = KITS.keys.sample
    gear = GEAR.keys.sample
    bpm = rand(85..98)
    key = %w[C C# D D# E F F# G G# A A# B].sample

    puts "random: #{pattern} | #{kit} | #{gear} | #{bpm}bpm | #{key}"

    beat = new(bpm: bpm, pattern: pattern, gear: gear, kit: kit, key: key)
    beat.make(output: output || "RANDOM_#{pattern}_#{kit}_#{bpm}bpm.wav")
  end

  def make(sample: nil, output: nil)
    puts "beat.rb #{VERSION}"
    puts "#{@bpm} bpm | #{@bars} bars | #{@duration.round(1)}s | #{@key} | kit:#{@kit_name}"

    output ||= "BEAT_#{@bpm}BPM_#{timestamp}.wav"

    # layer 1: sample
    sample_layer = process_sample(sample)

    # layer 2: kick
    kick_layer = build_kick

    # layer 3: snare
    snare_layer = build_snare

    # layer 4: hihat
    hihat_layer = build_hihat

    # layer 5: bass
    bass_layer = build_bass

    # mix layers
    mixed = mix_layers(sample_layer, kick_layer, snare_layer, hihat_layer, bass_layer)

    # master
    master(mixed, output)

    cleanup
    puts "done: #{output}"
    output
  end

  private

  def process_sample(sample)
    return nil unless sample && File.exist?(sample)

    puts "  sample: #{File.basename(sample)}"
    out = temp("sample.wav")

    # convert and apply sp character
    chain = [
      "atrim=duration=#{@duration}",
      "aresample=48000",
      "acrusher=bits=#{@gear[:bits]}:mode=lin",
      "volume=1.8,atanh,volume=0.555",
      "lowpass=f=#{@gear[:filter]}",
      "volume=0.6"
    ].join(",")

    ffmpeg("-i "#{sample}" -af "#{chain}" "#{out}"")
    out
  end

  def build_kick
    puts "  kick layer"
    kick_sample = find_kit_sample(:kick)
    return nil unless kick_sample

    delays = build_pattern_delays(:kick)
    out = temp("kick.wav")
    build_drum_layer(kick_sample, delays, out, 0.85)
    out
  end

  def build_snare
    puts "  snare layer"
    snare_sample = find_kit_sample(:snare)
    return nil unless snare_sample

    delays = build_pattern_delays(:snare)
    out = temp("snare.wav")
    build_drum_layer(snare_sample, delays, out, 0.75)
    out
  end

  def build_hihat
    puts "  hihat layer"
    hihat_sample = find_kit_sample(:hihat)
    return nil unless hihat_sample

    delays = build_pattern_delays(:hihat)
    out = temp("hihat.wav")
    build_drum_layer(hihat_sample, delays, out, 0.4)
    out
  end

  def build_bass
    puts "  bass layer"
    freq = note_freq(@key, 2)
    out = temp("bass.wav")

    # simple sine bass following kick pattern
    kick_delays = build_pattern_delays(:kick)
    return nil if kick_delays.empty?

    # generate bass tone
    ffmpeg("-f lavfi -i "sine=f=#{freq}:d=#{@duration}:r=48000" -af "lowpass=f=200,volume=0.6" "#{out}"")
    out
  end

  def build_pattern_delays(instrument)
    pattern_data = @pattern[instrument] || []
    nudge = TIMING[:nudge][instrument] || 0
    delays = []

    @bars.times do |bar|
      16.times do |step|
        next unless pattern_data[step] == 1

        base_ms = (bar * @bar_ms) + (step * @sixteenth_ms)
        delays << (base_ms + nudge).round
      end
    end

    delays
  end

  def build_drum_layer(sample, delays, output, volume)
    return if delays.empty?

    # build filter complex with adelay for each hit
    inputs = delays.each_with_index.map { |d, i| "[0:a]adelay=#{d}|#{d}[d#{i}]" }
    mix_refs = delays.each_with_index.map { |_, i| "[d#{i}]" }.join

    filter = "#{inputs.join(';')};#{mix_refs}amix=inputs=#{delays.length}:duration=longest,volume=#{volume}"

    ffmpeg("-i "#{sample}" -filter_complex "#{filter}" "#{output}"")
  end

  def mix_layers(*layers)
    layers = layers.compact.select { |f| File.exist?(f) }
    return nil if layers.empty?

    puts "  mixing #{layers.length} layers"
    out = temp("mixed.wav")

    if layers.length == 1
      FileUtils.cp(layers.first, out)
    else
      inputs = layers.map { |f| "-i "#{f}"" }.join(" ")
      refs = layers.each_with_index.map { |_, i| "[#{i}:a]" }.join
      filter = "#{refs}amix=inputs=#{layers.length}:duration=longest"
      ffmpeg("#{inputs} -filter_complex "#{filter}" "#{out}"")
    end

    out
  end

  def master(input, output)
    return unless input && File.exist?(input)

    puts "  mastering"
    chain = [
      "acrusher=bits=14:mode=lin",
      "volume=1.2,atanh,volume=0.833",
      "acompressor=threshold=-18dB:ratio=4:attack=5:release=50",
      "equalizer=f=100:width_type=q:width=0.8:g=3",
      "equalizer=f=8000:width_type=q:width=1.2:g=-2.5",
      "loudnorm=I=-16:TP=-1"
    ].join(",")

    ffmpeg("-i "#{input}" -af "#{chain}" "#{output}"")
  end

  def find_kit_sample(type)
    kit_path = File.join(SAMPLES_DIR, @kit[:path])
    pattern = @kit[type]

    # try kit-specific path first
    samples = Dir.glob("#{kit_path}/**/#{pattern}*.wav", File::FNM_CASEFOLD)
    return samples.sample if samples.any?  # random from available

    # fallback to general search
    samples = Dir.glob("#{SAMPLES_DIR}/**/#{pattern}*.wav", File::FNM_CASEFOLD)
    return samples.sample if samples.any?

    # last resort - any matching type
    fallback = { kick: "bd", snare: "sd", hihat: "hh" }
    samples = Dir.glob("#{SAMPLES_DIR}/**/#{fallback[type]}*.wav", File::FNM_CASEFOLD)
    samples.sample
  end

  def find_sample(pattern)
    # search in current dir first
    Dir.glob("**/#{pattern}*", File::FNM_CASEFOLD).first ||
      Dir.glob("#{SAMPLES_DIR}/**/#{pattern}*", File::FNM_CASEFOLD).first
  end

  def note_freq(note, octave = 4)
    semitones = { "C"=>0,"C#"=>1,"D"=>2,"D#"=>3,"E"=>4,"F"=>5,"F#"=>6,"G"=>7,"G#"=>8,"A"=>9,"A#"=>10,"B"=>11 }
    440.0 * (2.0 ** ((semitones[note.upcase].to_i - 9 + (octave - 4) * 12) / 12.0))
  end

  def ffmpeg(args)
    cmd = "ffmpeg -y -hide_banner -loglevel error #{args}"
    system(cmd) or raise "ffmpeg failed: #{cmd}"
  end

  def temp(name)
    path = File.join(Dir.tmpdir, "beat_#{$$}_#{name}")
    @temp_files << path
    path
  end

  def cleanup
    @temp_files.each { |f| File.delete(f) if File.exist?(f) }
  end

  def timestamp
    Time.now.strftime("%Y%m%d_%H%M%S")
  end

  # als parser - extracts bpm, patterns, samples from ableton projects
  class ALS
    attr_reader :bpm, :tracks, :samples

    def initialize(als_path)
      @als_path = als_path
      @tracks = []
      @samples = []
      @bpm = 120
      parse
    end

    def parse
      xml = Zlib::GzipReader.open(@als_path) { |gz| gz.read }
      doc = REXML::Document.new(xml)

      tempo = doc.elements["//Tempo/Manual"]
      @bpm = tempo&.attributes["Value"]&.to_f&.round || 120

      doc.elements.each("//Tracks/*") do |track|
        name = track.elements[".//Name/EffectiveName"]&.attributes["Value"] || "unnamed"
        type = track.name.gsub("Track", "").downcase

        info = { name: name, type: type, clips: [], samples: [] }

        track.elements.each(".//MidiClip") do |clip|
          notes = []
          clip.elements.each(".//KeyTracks/KeyTrack") do |kt|
            midi_key = kt.elements["MidiKey"]&.attributes["Value"]&.to_i || 0
            kt.elements.each(".//MidiNoteEvent") do |n|
              notes << {
                key: midi_key,
                time: n.attributes["Time"]&.to_f || 0,
                vel: n.attributes["Velocity"]&.to_i || 100
              }
            end
          end
          info[:clips] << { name: clip.elements[".//Name"]&.attributes["Value"], notes: notes }
        end

        track.elements.each(".//SampleRef/FileRef/Name") do |ref|
          info[:samples] << ref.attributes["Value"] if ref.attributes["Value"]
        end

        @tracks << info
        @samples.concat(info[:samples])
      end
    end

    def summary
      puts "#{File.basename(@als_path)} | #{@bpm} bpm | #{@tracks.length} tracks"
      @tracks.each do |t|
        next if t[:clips].empty? && t[:samples].empty?
        puts "  #{t[:type]}: #{t[:name]} (#{t[:clips].length} clips, #{t[:samples].length} samples)"
      end
      puts "  samples: #{@samples.uniq.length} unique"
    end

    def drum_pattern(regex)
      @tracks.each do |t|
        next unless t[:name] =~ regex
        t[:clips].each do |c|
          next unless c[:notes]&.any?
          pattern = Array.new(16, 0)
          c[:notes].each { |n| pattern[(n[:time] * 4).round % 16] = 1 }
          return pattern
        end
      end
      nil
    end

    def to_beat_config
      {
        bpm: @bpm,
        kick: drum_pattern(/kick|bd|bass.drum/i) || [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
        snare: drum_pattern(/snare|sd|clap/i) || [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
        hihat: drum_pattern(/hat|hh/i) || [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0],
        samples: @samples.uniq
      }
    end
  end

  # create beat from ableton project
  def self.from_als(als_path, output: nil)
    als = ALS.new(als_path)
    als.summary

    config = als.to_beat_config
    pattern = { kick: config[:kick], snare: config[:snare], hihat: config[:hihat] }

    beat = new(bpm: config[:bpm], pattern: pattern)
    beat.make(output: output || "#{File.basename(als_path, '.als')}_restored.wav")
  end
end

# cli
if __FILE__ == $PROGRAM_NAME
  opts = {
    bpm: 95,
    bars: 8,
    key: "C",
    pattern: :dilla_lazy,
    gear: :sp303,
    kit: :tr808,
    sample: nil,
    output: nil
  }

  ARGV.each do |arg|
    case arg
    when /^--bpm=(d+)$/      then opts[:bpm] = $1.to_i
    when /^--bars=(d+)$/     then opts[:bars] = $1.to_i
    when /^--key=([A-G]#?)$/i then opts[:key] = $1.upcase
    when /^--pattern=(w+)$/  then opts[:pattern] = $1.to_sym
    when /^--gear=(w+)$/     then opts[:gear] = $1.to_sym
    when /^--kit=(w+)$/      then opts[:kit] = $1.to_sym
    when /^--sample=(.+)$/    then opts[:sample] = $1
    when /^--output=(.+)$/    then opts[:output] = $1
    when /^--help$/
      puts <<~HELP
        beat.rb v#{Beat::VERSION} - unified dilla beat maker

        usage: ruby beat.rb [options]
               ruby beat.rb <file.als>    restore from ableton project
               ruby beat.rb random        generate random beat

        options:
          --bpm=95         tempo (default: 95)
          --bars=8         bar count (default: 8)
          --key=C          root key (default: C)
          --pattern=NAME   see patterns below
          --gear=NAME      sp1200, mpc3000, mpc60, sp303, s950, s900
          --kit=NAME       tr808, tr909, linndrum, cr78, dmx, lm1, tr505, tr626
          --sample=FILE    sample to chop
          --output=FILE    output filename

        patterns:
          dilla: dilla_lazy, dilla_bounce, dilla_donuts, dilla_fantastic
          boom_bap: boom_bap, boom_bap_hard, premier, pete_rock
          stones_throw: madlib, madvillainy
          brainfeeder: flylo
          trap: trap, trap_roll
          house: house
          breaks: breakbeat, amen
          funk: funk
          dub: one_drop, steppers

        example:
          ruby beat.rb --bpm=90 --pattern=dilla_bounce --kit=linndrum
          ruby beat.rb random
          ruby beat.rb zap_zap_zap.als
      HELP
      exit 0
    when /^random$/i
      Beat.random
      exit 0
    when /.als$/i
      Beat.from_als(arg)
      exit 0
    end
  end

  Beat.new(
    bpm: opts[:bpm],
    bars: opts[:bars],
    key: opts[:key],
    pattern: opts[:pattern],
    gear: opts[:gear],
    kit: opts[:kit]
  ).make(sample: opts[:sample], output: opts[:output])
end
