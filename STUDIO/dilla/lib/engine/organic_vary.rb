# frozen_string_literal: true
#
# Varying the loop each pass: pitch, time and tone walks, dropouts.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# A sampled loop played with -stream_loop is bit-identical every repetition, and
# nothing acoustic repeats exactly. ORGANIC_VARY=1 pre-builds the bed as N
# separately-processed copies so each pass differs slightly in pitch, tone and
# start offset -- the thing that stops a loop sounding stapled to the grid.
#
# Deliberately small numbers: past a few cents the loop stops agreeing with the
# generated harmony, and past ~15ms the drums stop agreeing with themselves.
ORGANIC_VARY = ENV["ORGANIC_VARY"] == "1"
ORGANIC_VARY_CENTS = (ENV["ORGANIC_VARY_CENTS"] || 4.0).to_f.clamp(0.0, 30.0)
ORGANIC_VARY_MS = (ENV["ORGANIC_VARY_MS"] || 8.0).to_f.clamp(0.0, 60.0)
ORGANIC_VARY_TONE_HZ = (ENV["ORGANIC_VARY_TONE_HZ"] || 1800).to_i

# Fixed walks, one value per repetition, cycling. Reproducibility again: a loop
# that varies differently on every render cannot be mixed against.
ORGANIC_VARY_PITCH_WALK = [0.0, 0.6, -0.4, 1.0, -0.8, 0.3, -1.0, 0.7].freeze
ORGANIC_VARY_TIME_WALK  = [0.0, -0.5, 0.8, -0.2, 0.6, -0.9, 0.3, -0.6].freeze
ORGANIC_VARY_TONE_WALK  = [0.0, -1.2, 0.8, -0.6, 1.4, -0.3, 0.5, -1.0].freeze

# Chopping, as opposed to repeating.
#
# ORGANIC_VARY already stops each pass being bit-identical, but it still plays
# the loop front to back every time. Chopping cuts it into slices and plays them
# in a different order per pass, which is what the sampler workflow actually
# did: the loop is raw material, not a part.
#
# The order is a fixed rotation rather than random. A shuffle that differs every
# render cannot be mixed against, and more importantly a rotation preserves
# which slice lands on the downbeat -- slice 0 stays first in most passes, so
# the bar still starts where the ear expects while its interior rearranges.
LOOP_CHOP_SLICES = (ENV["LOOP_CHOP_SLICES"] || 0).to_i.clamp(0, 16)

# Rotations applied per pass. The first is identity so pass 1 states the loop
# plainly before anything is done to it -- rearranging from the very first bar
# leaves the listener nothing to hear the rearrangement against.
LOOP_CHOP_ORDERS = [
  [0, 1, 2, 3, 4, 5, 6, 7],
  [0, 1, 2, 3, 4, 6, 5, 7],
  [0, 2, 1, 3, 4, 5, 7, 6],
  [0, 1, 3, 2, 4, 5, 6, 7],
  [0, 1, 2, 3, 6, 5, 4, 7],
].freeze

def loop_chop_order(pass, slices)
  base = LOOP_CHOP_ORDERS[pass % LOOP_CHOP_ORDERS.size]
  base.select { |i| i < slices } + (base.size...slices).to_a
end

def organic_vary_loop!(src, dest, duration:)
  return nil unless File.file?(src)

  one = audio_duration_sec(src).to_f
  return nil unless one.positive?

  reps = ((duration / one).ceil + 1).clamp(1, 64)
  parts = []
  chain = []
  reps.times do |i|
    cents = ORGANIC_VARY_CENTS * ORGANIC_VARY_PITCH_WALK[i % ORGANIC_VARY_PITCH_WALK.size]
    shift = ORGANIC_VARY_MS * ORGANIC_VARY_TIME_WALK[i % ORGANIC_VARY_TIME_WALK.size]
    tone  = ORGANIC_VARY_TONE_HZ * (1.0 + (0.18 * ORGANIC_VARY_TONE_WALK[i % ORGANIC_VARY_TONE_WALK.size]))
    rate  = (SAMPLE_RATE * (2.0**(cents / 1200.0))).round
    delay = [shift.round, 0].max
    parts.concat(["-i", src])
    # asetrate then aresample is a varispeed: pitch and length move together, as
    # a tape machine does, rather than a formant-preserving shift that would
    # sound processed.
    voice = "[#{i}:a]asetrate=#{rate},aresample=#{SAMPLE_RATE}," \
            "lowpass=f=#{tone.round},adelay=#{delay}|#{delay}"

    if LOOP_CHOP_SLICES > 1
      # Cut this pass into slices and play them in a rotation. The loop stops
      # being a part and becomes material, which is what a sampler workflow
      # does with it. 4ms edges on every slice: a hard cut mid-waveform clicks,
      # and a click on every slice boundary is the fastest way to make chopping
      # sound like a fault rather than a choice.
      order = loop_chop_order(i, LOOP_CHOP_SLICES)
      slice = one / LOOP_CHOP_SLICES
      chain << "#{voice}[p#{i}]"
      chain << "[p#{i}]asplit=#{LOOP_CHOP_SLICES}#{(0...LOOP_CHOP_SLICES).map { |n| "[p#{i}s#{n}]" }.join}"
      order.each_with_index do |src_slice, pos|
        chain << "[p#{i}s#{pos}]atrim=#{(src_slice * slice).round(4)}:" \
                 "#{((src_slice + 1) * slice).round(4)},asetpts=PTS-STARTPTS," \
                 "afade=t=in:st=0:d=0.004," \
                 "afade=t=out:st=#{[(slice - 0.004), 0].max.round(4)}:d=0.004[c#{i}_#{pos}]"
      end
      cats = (0...LOOP_CHOP_SLICES).map { |n| "[c#{i}_#{n}]" }.join
      chain << "#{cats}concat=n=#{LOOP_CHOP_SLICES}:v=0:a=1[v#{i}]"
    else
      chain << "#{voice}[v#{i}]"
    end
  end
  labels = (0...reps).map { |i| "[v#{i}]" }.join
  chain << "#{labels}concat=n=#{reps}:v=0:a=1[vcat]"
  chain << "[vcat]atrim=0:#{duration.round(3)},asetpts=PTS-STARTPTS[vout]"
  begin
    sh! "ffmpeg", "-y", *parts, "-filter_complex", chain.join(";"),
        "-map", "[vout]", "-ar", SAMPLE_RATE.to_s, "-ac", "2",
        "-c:a", "pcm_s16le", dest
    dmesg("organic vary: #{reps} passes, +-#{ORGANIC_VARY_CENTS}c / #{ORGANIC_VARY_MS}ms",
          unit: "harm0", parent: "dilla0")
    dest
  rescue StandardError => e
    warn "organic vary: #{e.message}"
    nil
  end
end

# Applies a modulation to a rendered file in place. `codec` lets the same code
# serve the intermediate WAV buses and the final mp3/wav master.
def organic_modulate!(path, bar_sec:, mode:, label:)
  return path unless File.file?(path)

  ext = File.extname(path)
  out = "#{path}.#{mode}#{ext.empty? ? '.wav' : ext}"
  chain = organic_breath_filters("0:a", "bout", bar_sec:, mode:)
  args = ext.downcase == ".wav" || ext.empty? ? ["-c:a", "pcm_s16le"] : codec_for(out)
  begin
    sh! "ffmpeg", "-y", "-i", path, "-filter_complex", chain.join(";"),
        "-map", "[bout]", "-ar", SAMPLE_RATE.to_s, "-ac", "2", *args, out
    FileUtils.mv(out, path)
    path
  rescue StandardError => e
    warn "organic #{label}: #{e.message}"
    FileUtils.rm_f(out)
    path
  end
end

def organic_breathe!(path, bar_sec:)
  return path unless ORGANIC_BREATH

  organic_modulate!(path, bar_sec:, mode: :breath, label: "breath")
end

# The swell goes on the FINISHED master, not the pad bus.
#
# On the pad bus it was inaudible in the mix and the measurements said so: at
# the 3 dB default the full-mix LRA did not move at all, 3.4 with and without.
# Two reasons, both structural. Drums and bass hold a constant level, so a pad
# swelling 3 dB moves the total by a fraction of that. And the master chain --
# AKMD's acompressor at 3:1, then loudnorm -- exists precisely to remove a few
# dB of slow level movement; asking it politely not to is not an option.
#
# Applied here the movement is common-mode across the whole track and nothing
# downstream gets to average it away or compress it out. The cost is honest and
# worth stating: the drums breathe too, because everything does.
def organic_swell_master!(path, bar_sec:)
  return path unless ORGANIC_SWELL

  organic_modulate!(path, bar_sec:, mode: :swell, label: "swell")
end

# Total silence for a fraction of a beat immediately before a downbeat.
#
# Not a fade and not a filter -- everything stops, then everything returns. The
# gap has to land just before the bar line rather than on it: silence AT the
# downbeat sounds like a dropout, silence leading INTO one sounds like the
# track was cut, and the ear fills in the missing beat. Applied post-master for
# the same reason the swell is -- a compressor would pump around the hole and
# turn a clean cut into a swell of its own.
DILLA_DROPOUT_EVERY = (ENV["DILLA_DROPOUT_EVERY"] || 0).to_i   # every Nth bar
DILLA_DROPOUT_BEATS = (ENV["DILLA_DROPOUT_BEATS"] || 0.25).to_f.clamp(0.05, 2.0)

def dilla_dropout!(path, bar_sec:)
  return path unless DILLA_DROPOUT_EVERY.positive? && File.file?(path)

  gap = (bar_sec / 4.0) * DILLA_DROPOUT_BEATS
  bar = bar_sec.round(5)
  # Mute while inside the last `gap` of a bar, on every Nth bar.
  cond = "gte(mod(t\\,#{bar})\\,#{(bar_sec - gap).round(5)})" \
         "*eq(mod(floor(t/#{bar})\\,#{DILLA_DROPOUT_EVERY})\\,#{DILLA_DROPOUT_EVERY - 1})"
  ext = File.extname(path)
  out = "#{path}.drop#{ext.empty? ? '.wav' : ext}"
  args = ext.downcase == ".wav" || ext.empty? ? ["-c:a", "pcm_s16le"] : codec_for(out)
  begin
    sh! "ffmpeg", "-y", "-i", path,
        "-af", "volume='if(#{cond}\\,0\\,1)':eval=frame",
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", *args, out
    FileUtils.mv(out, path)
    dmesg("dropout: #{(gap * 1000).round}ms before every #{DILLA_DROPOUT_EVERY} bars",
          unit: "mix0", parent: "dilla0")
    path
  rescue StandardError => e
    warn "dropout: #{e.message}"
    FileUtils.rm_f(out)
    path
  end
end
