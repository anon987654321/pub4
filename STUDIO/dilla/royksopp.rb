# frozen_string_literal: true

# Verified chord cells from Röyksopp's Melody A.M. era, used as harmonic source
# material for an original Dilla live arrangement. No melodies, recordings or
# original production are reproduced here.
module Royksopp
  SOURCES = {
    remind_me: {
      title: "Remind Me",
      chords: %w[Dm7 Am7 Ebmaj7 Bb],
      source: "Musicnotes/Cifra Club transcriptions; Melody A.M.",
    },
    shes_so: {
      title: "She's So",
      chords: %w[Dm7 Gm7 Ebmaj7 Abmaj7],
      source: "Chordify transcription; Melody A.M.",
    },
    so_easy_c_minor: {
      title: "So Easy / C-minor section",
      chords: %w[Cm Bb Dm],
      source: "Musicnotes/Cifra Club transcriptions; Melody A.M.",
    },
    so_easy_a_minor: {
      title: "So Easy / A-minor section",
      chords: %w[Am G Bm],
      source: "Musicnotes/Cifra Club transcriptions; Melody A.M.",
    },
    so_easy_e_minor: {
      title: "So Easy / E-minor section",
      chords: %w[Em Bm D],
      source: "Musicnotes/Cifra Club transcriptions; Melody A.M.",
    },
    eple: {
      title: "Eple",
      chords: %w[Db Fm Eb B Cm],
      source: "Hooktheory and ChordU transcriptions; Melody A.M.",
      tempo: 107,
      meter: "4/4",
    },
    poor_leno: {
      title: "Poor Leno",
      chords: %w[F# D#m A#m G#m B],
      source: "Yalp chord transcription; Melody A.M.",
      meter: "4/4",
    },
  }.freeze

  # A live suite, not the original arrangements: each verified progression is
  # given room to breathe while the Dilla engine changes patches, bass and drums.
  SUITE = [
    *SOURCES[:eple][:chords],
    *SOURCES[:eple][:chords],
    *SOURCES[:poor_leno][:chords],
    *SOURCES[:remind_me][:chords],
    *SOURCES[:shes_so][:chords],
    *SOURCES[:so_easy_c_minor][:chords],
    *SOURCES[:so_easy_a_minor][:chords],
    *SOURCES[:so_easy_e_minor][:chords],
  ].freeze

  # Upper chord tones plus a doubled root keep the pads four-note and lush while
  # preserving the written harmony: no added ninths or altered tones.
  VOICINGS = {
    m7: [3, 7, 10, 12],
    maj7: [4, 7, 11, 12],
    maj: [4, 7, 12, 16],
  }.freeze

  NOTE_PC = {
    "C" => 0, "Db" => 1, "C#" => 1, "D" => 2, "Eb" => 3, "D#" => 3,
    "E" => 4, "F" => 5, "Gb" => 6, "F#" => 6, "G" => 7, "Ab" => 8,
    "G#" => 8, "A" => 9, "Bb" => 10, "A#" => 10, "B" => 11,
  }.freeze

  module_function

  def chord(symbol)
    m = symbol.to_s.match(/\A([A-G](?:b|#)?)(m7|maj7|m|maj)?\z/) or raise ArgumentError, "bad Röyksopp chord #{symbol.inspect}"
    root = NOTE_PC.fetch(m[1])
    quality = (m[2] || "maj").to_sym
    { symbol: symbol.to_s, root_pc: root, tones: VOICINGS.fetch(quality).map { |interval| (root + interval) % 12 } }
  end

  def source_for(symbol)
    key = SOURCES.find { |_name, row| row[:chords].include?(symbol.to_s) }&.first
    key ? SOURCES.fetch(key) : nil
  end

  def source_titles
    SOURCES.values.map { |row| row[:title] }.uniq
  end
end


if $PROGRAM_NAME == __FILE__
  require "fileutils"
  require "json"
  require "sound"

  module RoyksoppLive
    RATE = 32_000
    BPM = (Royksopp::SOURCES[:eple][:tempo] || 107).to_f
    BEATS_PER_CHORD = 8
    CHORD_SECONDS = BEATS_PER_CHORD * 60.0 / BPM
    BLOCK = 1_024
    HOME = ENV.fetch("DILLA_LIVE_DIR") { File.join(Dir.tmpdir, "dilla-live-#{Process.uid}") }
    RECORD = File.join(HOME, "player.json")
    PATCHES = %i[warm_pad poly_strings prophet_pad juno_pad vp330_ensemble e_piano rhodes_tine].freeze
    Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phase, :ladder)

    def self.audio_tool(name)
      ["/opt/homebrew/bin/#{name}", "/usr/local/bin/#{name}",
       *ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }]
        .uniq.find { |path| File.executable?(path) && !File.directory?(path) }
    end

    def self.player_command
      sox = audio_tool("sox")
      return [sox, "-q", "-t", "raw", "-r", RATE.to_s, "-e", "signed", "-b", "16", "-c", "2", "-", "-d"] if sox
      ffplay = audio_tool("ffplay")
      return [ffplay, "-f", "s16le", "-ar", RATE.to_s, "-ac", "2", "-nodisp", "-autoexit", "-loglevel", "quiet", "-i", "-"] if ffplay
    end

    def self.claim!
      FileUtils.mkdir_p(HOME)
      File.write(RECORD, JSON.generate(pid: Process.pid, what: "röyksopp Melody A.M. chord pads",
                                        steerable: false, since: Time.now.strftime("%H:%M:%S")))
    end

    def self.release!
      row = File.file?(RECORD) ? JSON.parse(File.read(RECORD)) : nil
      FileUtils.rm_f(RECORD) if row && row["pid"].to_i == Process.pid
    rescue JSON::ParserError
      FileUtils.rm_f(RECORD)
    end

    def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

    def self.voice_lead(pcs, previous)
      notes = pcs.map do |pc|
        centre = previous.shift || 57
        (48..76).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end
      notes.sort
    end

    def self.render
      command = player_command or abort "royksopp: no local soundcard player — install sox or ffplay"
      player = IO.popen(command, "wb")
      stopped = false
      stop = lambda do
        stopped = true
        Process.kill("TERM", player.pid) rescue nil
        player.close rescue nil
      end
      trap("TERM", &stop)
      trap("INT", &stop)

      rng = Random.new(ENV.fetch("ROYKSOPP_SEED", Random.new_seed).to_i)
      voices = []
      previous = [53, 57, 60, 64]
      chord_i = 0
      next_chord = 0.0
      seconds = ENV.fetch("ROYKSOPP_SECONDS", "0").to_f
      finite = seconds.positive?
      limit = finite ? (seconds * RATE).ceil : nil
      frame = 0

      while !stopped && (!limit || frame < limit)
        now = frame.to_f / RATE
        while next_chord <= now + (BLOCK.to_f / RATE)
          symbol = Royksopp::SUITE[chord_i % Royksopp::SUITE.length]
          chord = Royksopp.chord(symbol)
          previous = voice_lead(chord[:tones], previous)
          patch = AnalogSynth::PATCHES.fetch(PATCHES[chord_i % PATCHES.length]).dup
          patch[:amp] = AnalogSynth::Envelope.new(attack: 0.55, decay: 0.8, sustain: 0.82, release: 1.8)
          patch[:filter_env] = AnalogSynth::Envelope.new(attack: 1.1, decay: 1.3, sustain: 0.72, release: 1.6)
          previous.each_with_index do |midi, i|
            voices << Voice.new(hz(midi) * (2.0**(rng.rand(-5.0..5.0) / 1200.0)),
                                patch, next_chord, CHORD_SECONDS - 0.1, 0.29 + (i.zero? ? 0.04 : 0.0),
                                patch[:waves].map { rng.rand }, AnalogSynth::Ladder.new(rate: RATE))
          end
          root = 36 + chord[:root_pc]
          bass_patch = AnalogSynth::PATCHES.fetch(:moog_bass).dup
          voices << Voice.new(hz(root), bass_patch, next_chord, CHORD_SECONDS * 0.8, 0.07,
                              bass_patch[:waves].map { rng.rand }, AnalogSynth::Ladder.new(rate: RATE))
          $stderr.puts "royksopp0: #{symbol} — #{Royksopp.source_for(symbol)&.fetch(:title, "Melody A.M.")}"
          chord_i += 1
          next_chord += CHORD_SECONDS
        end

        left = Array.new(BLOCK, 0.0)
        right = Array.new(BLOCK, 0.0)
        voices.delete_if { |voice| now > voice.start + voice.held + voice.spec[:amp].release }
        voices.each do |voice|
          spec = voice.spec
          next if now + BLOCK.to_f / RATE < voice.start || now > voice.start + voice.held + spec[:amp].release
          level = 1.0 / spec[:waves].size
          j = 0
          while j < BLOCK
            t = now + j.to_f / RATE - voice.start
            if t >= 0
              amp = spec[:amp].at(t, voice.held) * voice.gain
              env = spec[:filter_env].at(t, voice.held)
              sweep = 0.55 + 0.45 * Math.sin((now + t) / 9.0)
              cutoff = (spec[:cutoff] * sweep + spec[:env_amount] * env).clamp(40.0, 12_000.0)
              raw = spec[:waves].each_index.sum do |k|
                hz_now = voice.hz * 2.0**spec[:octaves][k] * 2.0**(spec[:detune][k] / 1200.0)
                voice.phase[k] = (voice.phase[k] + (hz_now / RATE)) % 1.0
                AnalogSynth.wave(spec[:waves][k], voice.phase[k]) * level
              end
              sample = voice.ladder.process(raw * spec[:drive], cutoff, [spec[:resonance], 0.82].min) * amp
              pan = spec.equal?(bass_patch) ? 0.0 : (Math.sin((now + t) / 17.0) * 0.04)
              left[j] += sample * (0.5 - pan)
              right[j] += sample * (0.5 + pan)
            end
            j += 1
          end
        end

        scale = 0.74
        pcm = Array.new(BLOCK * 2) do |i|
          sample = (i.even? ? left[i / 2] : right[i / 2]) * scale
          (sample.clamp(-1.0, 1.0) * 32_767).round
        end
        player.write(pcm.pack("s<*"))
        frame += BLOCK
      end
    ensure
      player&.close rescue nil
    end

    def self.call
      claim!
      render
    ensure
      release!
    end
  end

  RoyksoppLive.call
end
