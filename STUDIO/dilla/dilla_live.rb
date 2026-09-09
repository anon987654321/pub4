#!/usr/bin/env ruby
# frozen_string_literal: true

# The catalogue, generated and played as it goes.
#
# Thin on purpose. Every decision here is made somewhere else and this file only
# arranges them: the progressions come from the engine, the lines from
# ImprovisedLine, the instruments from AnalogSynth, the room from SpaceFx. What
# is left is the part that is genuinely this file's own -- pick an instrument,
# build a bar, hand the samples to a player, repeat.
#
# Not a render that is played afterwards. Each progression is synthesised into
# raw samples and written straight to a player's standard input, so nothing is
# ever written to disk. Stop it and there is no artifact, which is the point:
# this is for hearing. `dilla.rb` is what makes files.
#
# Back-pressure does the timing. The player's buffer fills, the write blocks,
# and the next bar is rendered only when there is room for it, so this runs at
# the speed of sound without needing a clock.
#
#   ruby dilla_live.rb              the catalogue, one instrument per progression
#   ruby dilla_live.rb 3            three times through
#   PATCH=surreal_wash              hold one instrument instead of rotating
#   LEAD=0 / BASS=0                 drop a layer
#   LEAD_DENSITY=1.0                more notes in the line
#   COPIES=6                        thicker Copy Machine cloud on the lead
#   REVERB=0.5 ECHO=0.4             wetter
#   CHORD_CADENCE=2.6,0.7,0.7,1.5   chord lengths, cycled

require_relative "dilla"
require_relative "lib/space_fx"

module DillaLive
  RATE = AnalogSynth::RATE

  class << self
    # Chord lengths, cycled, read exactly as the audition reads them.
    def cadence
      given = ENV["CHORD_CADENCE"].to_s.split(",").map { |v| v.to_f.clamp(0.15, 12.0) }.select(&:positive?)
      return given unless given.empty?

      [(ENV["CHORD_HOLD"] || "1.6").to_f.clamp(0.2, 8.0)]
    end

    # One progression as three layers of notes, plus how long it runs.
    def build(track, rng)
      names = CHORD_PROGRESSIONS[track] or return nil
      # Resolved up front: the bass has to know where the harmony is going
      # before it can walk toward it, and the lead before it can land on it.
      chords = names.filter_map do |name|
        chord = resolve_pad_chord_symbol(name)
        hz = Array(chord && chord[:hz]).map(&:to_f).select(&:positive?)
        hz unless hz.empty?
      end
      return nil if chords.empty?

      lengths = cadence
      pad = []
      lead = []
      bass = []
      at = 0.0
      chords.each_with_index do |hz, i|
        held = lengths[i % lengths.length]
        hz.each { |f| pad << { hz: f, at: at.round(4), held:, gain: 0.55 } }
        lead.concat(ImprovisedLine.lead(hz, chords[i + 1], at, held, rng)) if ENV["LEAD"] != "0"
        bass.concat(ImprovisedLine.bass(hz, chords[i + 1]&.min, at, held, rng)) if ENV["BASS"] != "0"
        at += held
      end

      # The Copy Machine on the line only. On the pad it would double a sound
      # that is already five oscillators wide; on a sparse line it is the
      # difference between one note and a cloud arriving after it.
      copies = (ENV["COPIES"] || "4").to_i
      lead = ImprovisedLine.copies(lead, copies:, seed: rng.seed % 100_000) if copies > 1

      [pad, lead, bass, at + 4.0]
    end

    # Pad dry, bass dry, and everything spatial spent on the line.
    #
    # Reverb on a pad that is already a wash makes mud, and reverb on a bass
    # takes away the only thing a bass has to be, which is definite. The lead is
    # the layer with gaps in it, and a room is only audible in the gaps.
    def render(pad, lead, bass, patch, duration, seed)
      layers = []
      layers << [{ patch:, notes: pad }] unless pad.empty?
      layers << [{ patch: :dub_bass, notes: bass }] unless bass.empty?

      left = nil
      right = nil
      layers.each do |groups|
        l, r = AnalogSynth.buffers!(groups, duration:, seed:)
        next unless l

        left ? mix!(left, right, l, r) : (left = l) && (right = r)
      end

      unless lead.empty?
        l, r = AnalogSynth.buffers!([{ patch: lead_patch, notes: lead }], duration:, seed:)
        if l
          plan = SpaceFx.random_plan(Random.new(seed), wet: (ENV["WET"] || "1.0").to_f,
                                     max_stages: @max_stages)
          @last_chain = SpaceFx.describe(plan)
          # The two channels get different comb lengths, so the room is not the
          # same room played twice -- which is the whole of why it sounds like a
          # space rather than like an effect.
          SpaceFx.apply!(l, plan, spread: 0)
          SpaceFx.apply!(r, plan, spread: 23)
          left ? mix!(left, right, l, r) : (left = l) && (right = r)
        end
      end
      return nil unless left

      AnalogSynth.interleave(left, right)
    end

    attr_reader :last_chain

    # The lead voices, which rotate unless one is named. Saws are deliberately
    # absent: alone in a high register over a pad there is nothing to mask their
    # upper partials, and what should read as a voice reads as a fault.
    LEAD_PATCHES = %i[glass_bell soft_reed vapor_lead ringtone_lead].freeze

    def lead_patch
      named = ENV["LEAD_PATCH"].to_s.strip.to_sym
      return named if AnalogSynth::PATCHES.key?(named)

      @lead_index = (@lead_index || -1) + 1
      LEAD_PATCHES[@lead_index % LEAD_PATCHES.length]
    end

    def mix!(left, right, add_l, add_r)
      i = 0
      while i < left.length && i < add_l.length
        left[i] += add_l[i]
        right[i] += add_r[i]
        i += 1
      end
    end

    # sox first, and not as a fallback: ffplay takes no -ac, so the obvious
    # stereo invocation of it dies on "Option not found" with the pipe already
    # open, which surfaces as a broken pipe seconds later and looks like
    # anything but a bad argument.
    def player_command
      if (play = which("play"))
        [play, "-q", "-t", "raw", "-r", RATE.to_s, "-e", "signed", "-b", "16", "-c", "2", "-"]
      elsif (ffplay = which("ffplay"))
        [ffplay, "-hide_banner", "-loglevel", "error", "-nodisp", "-autoexit",
         "-f", "s16le", "-ar", RATE.to_s, "-ch_layout", "stereo", "-i", "-"]
      end
    end

    def which(bin)
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR)
                 .map { |dir| File.join(dir, bin) }
                 .find { |path| File.executable?(path) && !File.directory?(path) }
    end

    # The same signal path, written to a file instead of to the speakers.
    #
    # Worth having for one reason: what plays here is not what `dilla.rb`
    # renders -- different lines, different instruments, an effect chain drawn
    # per progression -- so without this there is no way to keep a pass you
    # liked. Same samples, one pipe further.
    def writer_command(dest)
      ffmpeg = which("ffmpeg") or abort "dilla_live: --render needs ffmpeg"
      FileUtils.mkdir_p(File.dirname(dest))
      [ffmpeg, "-y", "-loglevel", "error", "-f", "s16le", "-ar", RATE.to_s,
       "-ac", "2", "-i", "-", "-c:a", "pcm_s16le", dest]
    end

    def run(passes, dest = nil)
      command = dest ? writer_command(dest) : player_command
      abort "dilla_live: needs sox's play or ffplay on PATH" unless command

      # A render has all the time in the world; playing has until the speaker
      # wants the next sample. FX_STAGES overrides either way.
      @max_stages = (ENV["FX_STAGES"] || (dest ? "9" : "3")).to_i
      order = demo_curated_order
      held = ENV["PATCH"].to_s.strip.to_sym
      hold_one = AnalogSynth::PATCHES.key?(held)
      puts "live: #{order.length} progressions, #{hold_one ? held : 'rotating instruments'} — ctrl-c to stop"

      IO.popen(command, "wb") do |speaker|
        pass = 0
        while passes.zero? || pass < passes
          order.each_with_index do |track, i|
            patch = hold_one ? held : PATCH_ROTATION[i % PATCH_ROTATION.length]
            # Seeded on the track and the pass, so the line is different the
            # second time round and reproducible either time.
            rng = Random.new(DillaImprovisation.seed + (pass * 1000) + i)
            built = build(track, rng) or next

            pad, lead, bass, duration = built
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            pcm = render(pad, lead, bass, patch, duration, DillaImprovisation.seed + i)
            next unless pcm

            spent = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            puts format("  %-24s %-13s %5.1fs in %4.1fs (%.2fx)",
                        track, patch, duration, spent, duration / spent)
            puts "      #{last_chain}" if last_chain
            speaker.write(pcm)
          end
          pass += 1
        end
      end
    rescue Errno::EPIPE, Interrupt
      puts "\nstopped"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  # Ruby buffers stdout when it is not a terminal, so a redirected run shows
  # nothing for the first several progressions and looks stalled while it is
  # playing perfectly well.
  $stdout.sync = true
  require "fileutils"
  dest = nil
  if (i = ARGV.index("--render"))
    dest = ARGV[i + 1] or abort "usage: dilla_live.rb [passes] --render <out.wav>"
    ARGV.delete_at(i + 1)
    ARGV.delete_at(i)
  end
  # A render has to end, so it defaults to one pass where playing defaults to
  # forever.
  DillaLive.run((ARGV.shift || (dest ? "1" : "0")).to_i, dest)
end
