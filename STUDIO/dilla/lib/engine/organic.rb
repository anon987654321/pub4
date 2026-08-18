# frozen_string_literal: true
#
# Organic movement: breath, swell, and letting the sample drive the pads.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- breathing --------------------------------------------------------------
#
# The engine already owns vibrato, chorus, tremolo, phaser and a drift filter.
# More of those does not make a pad breathe, because all of them are periodic,
# independent and fixed-rate: three unrelated motions at constant speed read as
# a static sound with effects on it. Two things are missing.
#
# ORGANIC_BREATH=1  drives loudness and brightness from ONE control signal, so
#   the pad gets louder and brighter together the way a played instrument does
#   when the player pushes. Correlation is the whole point; two independent
#   modulations at the same depths do not sound like this.
#
# ORGANIC_SWELL=1   swells across the phrase and relaxes out of it -- the
#   literal breath. Measured motivation: renders here come out at LRA 2.9, so
#   bar 1 and bar 17 are equally loud, which no played performance is.
# Default on. One control signal drives loudness and brightness together, which
# is how an acoustic source behaves — playing louder is also playing brighter.
ORGANIC_BREATH = ENV.fetch("ORGANIC_BREATH", "1") != "0"
# Default on. Swells across a phrase and relaxes out of it, so a loop stops
# arriving at every bar with identical energy.
ORGANIC_SWELL = ENV.fetch("ORGANIC_SWELL", "1") != "0"
ORGANIC_BREATH_DB = (ENV["ORGANIC_BREATH_DB"] || 2.2).to_f.clamp(0.0, 12.0)
ORGANIC_SWELL_DB = (ENV["ORGANIC_SWELL_DB"] || 3.0).to_f.clamp(0.0, 12.0)
ORGANIC_SWELL_BARS = (ENV["ORGANIC_SWELL_BARS"] || 4).to_f.clamp(1.0, 32.0)
# How dark the closed end of the brightness sweep is. The bright branch is the
# untouched signal, so this is the only tone control here.
ORGANIC_DARK_HZ = (ENV["ORGANIC_DARK_HZ"] || 1400).to_i

# Three incommensurate rates. A single LFO at 0.13 Hz repeats every 7.7s and the
# ear learns it; periods of 27s, 16s and 11s sum to something whose repeat is
# far longer than any track, so it never settles into a pattern. Fixed rather
# than random so a render reproduces -- an irregularity you cannot get back is
# an accident, not a character.
ORGANIC_RATES = [[0.037, 0.45, 0.0], [0.061, 0.35, 1.3], [0.089, 0.20, 2.7]].freeze

# Control signal in 0..1, as an ffmpeg expression over t.
def organic_control_expr
  terms = ORGANIC_RATES.map do |hz, amp, phase|
    "#{amp}*sin(2*PI*#{hz}*t+#{phase})"
  end
  "(0.5+0.5*(#{terms.join('+')}))"
end

# Raised cosine over the phrase: quietest at the phrase boundary, fullest in the
# middle, so it lands with the chord changes instead of cutting across them.
def organic_swell_expr(bar_sec)
  phrase = (bar_sec * ORGANIC_SWELL_BARS).round(4)
  "(0.5-0.5*cos(2*PI*t/#{phrase}))"
end

# Returns filter fragments taking [in_label] to [out_label].
#
# Brightness is done by crossfading a full-band branch against a lowpassed one,
# because ffmpeg's lowpass takes a fixed frequency and cannot be swept. Summing
# a dark copy and a bright copy under complementary time-varying gains gets the
# same result with filters that do support per-frame evaluation.
def organic_breath_filters(in_label, out_label, bar_sec:, mode: :breath)
  drive = mode == :swell ? organic_swell_expr(bar_sec) : organic_control_expr
  depth = mode == :swell ? ORGANIC_SWELL_DB : ORGANIC_BREATH_DB
  # Centred on 0 dB so the average level is unchanged and this is heard as
  # movement rather than as a level change.
  gain = "(#{depth}*(#{drive}-0.5)*2)"

  [
    "[#{in_label}]asplit=2[br_a][br_b]",
    "[br_a]volume=#{'%.4f' % 1.0}:eval=frame[br_bright]",
    "[br_b]lowpass=f=#{ORGANIC_DARK_HZ}[br_dark]",
    # Bright rises with the drive, dark falls: same signal, tone opening and
    # closing with the loudness rather than on its own schedule.
    "[br_bright]volume='#{drive}':eval=frame[br_bw]",
    "[br_dark]volume='(1-#{drive})':eval=frame[br_dw]",
    "[br_bw][br_dw]amix=inputs=2:normalize=0[br_mix]",
    "[br_mix]volume='exp(#{gain}*0.11512925)':eval=frame[#{out_label}]",
  ]
end

# The sample drives the synths, instead of merely sitting beside them.
#
# Until now the loop and the generated parts have coexisted without ever
# touching: HARMONIC_KEEP puts them in the same key, the mix puts them at
# compatible levels, and that is the whole of their relationship. This makes
# the loop the control signal -- its amplitude envelope shapes the pad bus, so
# when the sample moves the pads move with it, and the two read as one
# instrument rather than as two things playing at once.
#
# amultiply against a smoothed, floored envelope rather than sidechaincompress:
# a compressor ducks below a threshold and is otherwise absent, while
# multiplying imposes the sample's shape continuously. The floor stops the pads
# vanishing in the loop's gaps -- at 0 this becomes a gate and the harmony
# disappears wherever the sample rests, which is a different effect entirely.
SAMPLE_DRIVES_PADS = (ENV["SAMPLE_DRIVES_PADS"] || 0).to_f.clamp(0.0, 1.0)
SAMPLE_DRIVE_FLOOR = (ENV["SAMPLE_DRIVE_FLOOR"] || 0.45).to_f.clamp(0.0, 1.0)
SAMPLE_DRIVE_SMOOTH_HZ = (ENV["SAMPLE_DRIVE_SMOOTH_HZ"] || 14).to_i

def sample_drives_pads!(harmonic_path, loop_path, duration:)
  return harmonic_path unless SAMPLE_DRIVES_PADS.positive?
  return harmonic_path unless harmonic_path && loop_path
  return harmonic_path unless File.file?(harmonic_path) && File.file?(loop_path)

  env_path = "#{harmonic_path}.drive.wav"
  out = "#{harmonic_path}.driven.wav"
  depth = SAMPLE_DRIVES_PADS
  floor = 1.0 - ((1.0 - SAMPLE_DRIVE_FLOOR) * depth)
  begin
    sh! "ffmpeg", "-y", "-stream_loop", "-1", "-i", loop_path,
        "-af", "highpass=f=80,lowpass=f=6000," \
               "aeval=abs(val(0))|abs(val(1))," \
               "lowpass=f=#{SAMPLE_DRIVE_SMOOTH_HZ}," \
               "volume=#{(1.0 - floor).round(4)}," \
               "aeval=val(0)+#{floor.round(4)}|val(1)+#{floor.round(4)}," \
               "atrim=0:#{duration.round(3)},apad=whole_dur=#{duration.round(3)}",
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", env_path
    sh! "ffmpeg", "-y", "-i", harmonic_path, "-i", env_path,
        "-filter_complex",
        "[0:a]atrim=0:#{duration.round(3)},apad=whole_dur=#{duration.round(3)}[pads];" \
        "[pads][1:a]amultiply,alimiter=limit=0.95:level_out=0.96[out]",
        "-map", "[out]", "-ar", SAMPLE_RATE.to_s, "-ac", "2",
        "-c:a", "pcm_s16le", out
    FileUtils.mv(out, harmonic_path)
    dmesg("sample drives pads: depth #{depth}, floor #{floor.round(2)}",
          unit: "harm0", parent: "dilla0")
    harmonic_path
  rescue StandardError => e
    warn "sample drives pads: #{e.message}"
    FileUtils.rm_f(out)
    harmonic_path
  ensure
    FileUtils.rm_f(env_path)
  end
end
