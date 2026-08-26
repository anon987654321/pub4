# frozen_string_literal: true
#
# The drum bus filter: smooth vs hard kits, width, build-ups.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def build_drum_bus_filter(cfg, sonic, duration: nil)
  crush_mix = sonic&.dig("synth", "crush_mix")&.to_f
  base = if crush_mix&.positive?
           { bits: 12, samples: 1.69, mix: crush_mix.clamp(0.08, 0.55) }
         elsif cfg[:style_family] == :dilla
           { bits: 11, samples: 1.5, mix: 0.22 }
         else
           { bits: 8, samples: 1.2, mix: 0.12 }
         end
  haas = cfg[:style_family] == :flylo ? ",adelay=0|12" : ""
  # Grit as a per-track compositional choice, not a fixed mix-bus setting
  # — cleaner through the exposition, dirtiest through the development
  # section, pulled back as the build lands. A producer varying the dirt
  # on purpose, not one static crush knob for the whole record.
  crush =
    if duration && duration > 20
      third = (duration / 3.0).round(2)
      [
        "acrusher=bits=#{base[:bits] + 2}:samples=#{base[:samples]}:mix=#{(base[:mix] * 0.5).round(2)}:enable='lt(t,#{third})'",
        "acrusher=bits=#{base[:bits]}:samples=#{base[:samples]}:mix=#{(base[:mix] * 1.4).clamp(0.0, 0.6).round(2)}:enable='between(t,#{third},#{(third * 2).round(2)})'",
        "acrusher=bits=#{base[:bits] + 1}:samples=#{base[:samples]}:mix=#{base[:mix]}:enable='gte(t,#{(third * 2).round(2)})'",
      ].join(",") + ","
    else
      "acrusher=bits=#{base[:bits]}:samples=#{base[:samples]}:mix=#{base[:mix]},"
    end
  kick_boost = if flylo_primary_drums?
                 6.5
               elsif cfg[:style_family] == :dilla
                 3.5
               else
                 0.58
               end
  # Bus fader. Comfort / explicit DRUM_BUS_VOL wins over the old hot FlyLo path.
  base_vol = if ENV["DRUM_BUS_VOL"] && !ENV["DRUM_BUS_VOL"].empty?
               ENV["DRUM_BUS_VOL"].to_f.round(3)
             elsif flylo_primary_drums?
               1.35
             else
               (0.24 * kick_velocity_scale + 0.1).round(2)
             end
  # 1.26 is +2 dB on the whole drum bus, raised from 1.0 on operator instruction
  # 2026-08-10 ("make drums louder"). One multiplier, so it lifts kit and
  # sample-kick together and does not re-balance anything inside the bus.
  #
  # The FlyLo path keeps 1.4: it is already the hot branch and stacking a raise
  # on top of it is how the drums got called "too hard" before.
  #
  # Tune with DRUM_BUS_GAIN rather than editing this — the env var wins, and
  # every preset hash below carries its own value that this does not touch.
  bus_gain = ENV.fetch("DRUM_BUS_GAIN", flylo_primary_drums? ? "1.4" : "1.26").to_f
  drum_vol = (ENV["DEBUG_DRUM_WEIGHT"] || (base_vol * bus_gain).round(3)).to_s
  drum_air = ENV.fetch("DRUM_AIR_DB", "2.5").to_f
  drum_pres = ENV.fetch("DRUM_PRESENCE_DB", "2.5").to_f
  kick_boost = comfort_mode? ? [kick_boost, 1.2].min : kick_boost
  flylo_eq = if flylo_drum_overlay_enabled? && !comfort_mode?
               # Was stacking +5/+2.5/+4.9/+3.5dB across bass, low-mid, presence,
               # and air all at once -- direct feedback that the drums sound
               # "too hard" pointed at this chain. Presence/air were the biggest
               # offenders (harsh hat/snare crack); eased all four back.
               "equalizer=f=70:t=o:w=0.9:g=3.2,equalizer=f=200:t=o:w=1:g=1.6," \
                 "equalizer=f=4200:t=o:w=1.2:g=#{(2.2 + drum_pres * 0.25).round(1)}," \
                 "equalizer=f=6500:t=o:w=1.5:g=#{(1.3 + drum_air * 0.25).round(1)},"
             elsif drum_air.positive? || drum_pres.positive?
               "equalizer=f=3500:t=h:w=1600:g=#{drum_pres.round(1)}," \
                 "equalizer=f=7000:t=h:w=2200:g=#{drum_air.round(1)},"
             else
               ""
             end
  # The drum bus had no fade of any kind, so every render opened on a full-level
  # kit at t=0 while the harm bus waited until bar 2 to fade in
  # (harm_fade_start in the mix assembly). Direct feedback that "the beginning
  # is abrupt" points here: the first thing you hear is a cold hit at full
  # gain, with nothing under it. One bar of qsin is enough to read as a
  # downbeat arriving rather than a tape splice, and it stays out of the way of
  # the harm fade that follows it.
  #
  # Skipped on short renders (the 8-bar probe/preview path) where a whole bar of
  # fade would be an eighth of the render. DRUM_FADE_IN=0 disables it.
  bar_sec = 4.0 * 60.0 / (cfg[:bpm] || DEFAULT_BPM).to_f
  drum_fade = if ENV["DRUM_FADE_IN"] == "0" || duration.to_f <= 20
                ""
              else
                "afade=t=in:st=0:d=#{bar_sec.round(2)}:curve=qsin,"
              end
  head = "[0:a]aformat=channel_layouts=stereo,#{bus_analog_filter(:drums)}volume=#{drum_vol}," \
         "#{drum_fade}equalizer=f=480:t=h:w=420:g=-1.5,#{flylo_eq}"
  # chomp the comma first: head ends comma-terminated so the next filter can be
  # appended, and pinning a label straight onto it yields ",[d_pre]" -- which
  # ffmpeg parses as an empty filter name and rejects the whole graph.
  head = "#{head.chomp(',')}[d_pre];#{drum_width_stage('d_pre', 'd_wide')}[d_wide]" if drum_width.positive?
  tail = "equalizer=f=55:t=o:w=0.7:g=#{kick_boost},highpass=f=25#{haas}"
  return smooth_drum_bus_filter(head, tail) if smooth_drums?

  "#{head}#{crush}" \
    "acompressor=threshold=-14dB:ratio=2.2:attack=3:release=60" \
    "#{hard_drums? ? "[d_soft];#{hard_drum_stage('d_soft', 'd_hard')}[d_hard]" : ','}" \
    "#{tail}[drums]"
end

def smooth_drums?
  ENV.fetch("SMOOTH_DRUMS", "0") != "0"
end

def hard_drums?
  ENV.fetch("HARD_DRUMS", "0") != "0"
end

# Harder is not the opposite of smoother, and this composes with SMOOTH_DRUMS
# rather than fighting it.
#
# Smooth meant no grit: the bit-crusher gone, its harmonic density replaced by
# parallel compression. Hard means more impact, which is a transient question,
# not a distortion one. The two ask for different things and both can hold --
# what you cannot have is grit and impact at once, because quantisation noise
# sits on top of the attack and masks it.
#
# The click band is high-passed before it is compressed, so the fast attack
# works on stick and beater noise instead of being triggered by kick
# fundamental -- a full-band fast compressor ducks the whole kit every time the
# kick lands, which reads as pumping rather than punch. Blended under, so the
# body of the hit is untouched.
#
# 55 Hz is weight and 3.2 kHz is where a snare reads as crack. Both narrow, so
# they add impact at the two frequencies that carry it rather than making the
# whole kit louder, which the master stage would only take back out.
HARD_DRUM_CLICK_HP = 1800

# Measured on a finished take: the drum bus is 36 dB down side-to-mid, which is
# nearly a point source, and it is 9.5 dB louder than the harmonic bus.
# So the loudest thing in the mix is mono, and the stereo thing is underneath
# it -- which is why the finished master reads as mono (-46 to -65 dB side/mid)
# while the harmonic stem on its own is a healthy -7, and real records sit at
# -3 to -6.
#
# Widening above 250 Hz only. The kick and the low body stay where they are,
# because low-frequency stereo is what mono_bass exists to undo and moving it
# would fight the last stage of every rack.
DRUM_WIDTH_HZ = 250

def drum_width
  ENV.fetch("DRUM_WIDTH", "0").to_f.clamp(0.0, 1.0)
end

def drum_width_stage(input, output)
  amt = drum_width
  return "[#{input}]anull[#{output}];" if amt <= 0.0

  # haas, not stereowiden. Every sample in the kit is a mono file -- measured,
  # all of kick/snare/hat/clap/ghost are single-channel -- so the drum bus has
  # no left-right difference at all and stereowiden has nothing to widen. It
  # moved the bus 0.4 dB and I mistook that for a tuning problem.
  #
  # haas synthesises an image instead of enlarging one: a few milliseconds of
  # delay on one channel, which the ear reads as direction rather than as echo
  # below the ~30 ms fusion limit. That is the only thing that makes a stereo
  # field out of a mono source.
  #
  # Still above 250 Hz only. A Haas delay on the kick would smear its attack and
  # then be folded back by mono_bass at the end of every rack anyway.
  "[#{input}]asplit=2[dw_lo][dw_hi];" \
  "[dw_lo]lowpass=f=#{DRUM_WIDTH_HZ}[dw_low];" \
  "[dw_hi]highpass=f=#{DRUM_WIDTH_HZ}," \
  "haas=left_delay=#{(2.0 + 6.0 * amt).round(2)}:right_delay=#{(0.6 + 1.4 * amt).round(2)}:" \
  "left_balance=-#{(0.3 * amt).round(2)}:right_balance=#{(0.3 * amt).round(2)}:" \
  "side_gain=#{(1.0 + 0.6 * amt).round(2)}[dw_wide];" \
  "[dw_low][dw_wide]amix=inputs=2:weights=1 1:duration=first:normalize=0[#{output}];"
end

def hard_drum_stage(input, output)
  "[#{input}]asplit=2[hd_body][hd_click];" \
  "[hd_click]highpass=f=#{HARD_DRUM_CLICK_HP},acompressor=threshold=-34dB:ratio=6:attack=0.3:release=45," \
  "volume=2.5dB[hd_tick];" \
  "[hd_body][hd_tick]amix=inputs=2:weights=1 0.5:duration=first:normalize=0," \
  "equalizer=f=55:t=o:w=0.8:g=2.2," \
  "equalizer=f=3200:t=o:w=1.6:g=2.0[#{output}];"
end

# Weight without grit.
#
# The crusher above is doing two jobs at once: it adds harmonic density, which
# is what makes the kit feel dense and present, and it adds quantisation noise,
# which is the audible grit. Asking for EQ'd drums with no crushing means
# keeping the first job and dropping the second, so removing the crusher alone
# would leave the kit thinner than before rather than smoother.
#
# Parallel compression is the documented way to get the density back: a hard-
# compressed copy blended under the untouched one raises the body and the tail
# while the dry path keeps its transients. Standard practice on this genre's
# drum bus, and it is why the split exists here rather than a single heavier
# compressor, which would flatten the attack the crusher was never touching.
#
# The tonal moves are the "EQ'd" half: 300 clears the boxiness the crusher used
# to mask, 3k is held down because parallel compression pushes presence forward,
# and the shelf above 9k opens the top the removed bit-reduction was dulling.
def smooth_drum_bus_filter(head, tail)
  "#{head}asplit=2[d_dry][d_par];" \
  "[d_par]acompressor=threshold=-30dB:ratio=8:attack=1:release=120," \
  "equalizer=f=180:t=o:w=1.1:g=2.0,lowpass=f=7000[d_pc];" \
  "[d_dry][d_pc]amix=inputs=2:weights=1 0.42:duration=first:normalize=0," \
  "equalizer=f=300:t=o:w=1.2:g=-2.2," \
  "equalizer=f=3000:t=o:w=1.4:g=-1.6," \
  "equalizer=f=9000:t=h:w=6000:g=1.4," \
  "acompressor=threshold=-14dB:ratio=2.2:attack=6:release=90" \
  "#{hard_drums? ? "[d_soft];#{hard_drum_stage('d_soft', 'd_hard')}[d_hard]" : ','}" \
  "#{tail}[drums]"
end

def build_up_filter_enhanced(input_tag, duration, out_tag: "built")
  start_t = (duration * 0.82).round(2)
  "[#{input_tag}]" \
    "equalizer=f=4500:t=h:w=5000:g=3.5:enable='gte(t,#{start_t})'," \
    "equalizer=f=220:t=o:w=1.8:g=2.5:enable='gte(t,#{start_t})'[#{out_tag}]"
end
