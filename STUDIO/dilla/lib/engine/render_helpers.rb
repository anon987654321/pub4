# frozen_string_literal: true
#
# Small render helpers shared across the engines.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Hands the record and this track's chords to SampleFlip, and returns a loop
# entry pointing at what comes back.
#
# The returned entry claims the render's own tempo. That is not a fib: the flip
# was assembled beat by beat at that tempo, so the varispeed stage downstream
# has nothing left to correct and correctly does nothing.
# Off by default, and the reason matters more than the switch.
#
# A flip cuts a record into pieces and plays a new line from them. That is
# Dilla's method and it is right for the records he used, where a piece was
# itself a musical unit -- a chord stab, a bass note, a horn hit. Cut those up
# and reorder them and you get a new tune out of old parts.
#
# These chops are not that. They are flowing melodic passages off an Ethiopian
# broadcast, and the reason they are worth having is the melody running through
# them. Cutting a melody into sixteen fragments and reordering by pitch destroys
# the one thing that made it beautiful; what comes back has the right notes in
# the wrong order. Played straight, the loop is better, and the operator's
# judgement on hearing both was blunt about it.
#
# So the loop plays, as it did. FLIP=1 for records where chopping is the point.
def flip_loop_entry(entry, cfg, pads, n_bars)
  return entry unless ENV["FLIP"] == "1"
  return entry if entry.nil? || !File.file?(entry[:path].to_s)

  tones = chord_pitch_classes(pads)
  return entry if tones.empty?

  dest = dilla_render_tmp("flip")
  records = flip_sources(entry, cfg)
  # Voices from whichever of those records had any. Three of the eight chops do;
  # the rest are instrumental passages, which is what the chop scorer was
  # looking for in the first place.
  voices = ENV["VOCAL_CHOPS"] == "0" ? [] : records.filter_map { |p| VocalChop.for_loop(p) }
  result = SampleFlip.build!(
    loop_path: records, vocal_path: voices, dest:, bpm: cfg[:bpm].to_f,
    bars: n_bars, chord_tones: tones,
    seed: stable_hash("flip:#{cfg[:track]}")
  )
  unless result
    dmesg("flip: #{File.basename(entry[:path])} yielded too few usable pieces — looping instead",
          unit: "harm0", parent: "dilla0")
    return entry
  end

  # Name the records, not "loop.wav" -- every chop is called loop.wav, so the old
  # line said the same thing for all eight tracks and said nothing about the
  # second record at all.
  crate = records.map { |p| File.basename(File.dirname(p)) }
  vocal_note = result[:vocal_events].to_i.positive? ? ", #{result[:vocal_events]} vocal" : ""
  dmesg("flip: #{result[:slices]} pieces off #{crate.join(' + ')}, " \
        "#{result[:events]} notes over #{tones.length} chords, " \
        "#{result[:reversed]} reversed#{vocal_note}",
        unit: "harm0", parent: "dilla0")
  entry.merge(path: result[:path], bpm: cfg[:bpm].to_f, flipped: true)
end

# Plays a chord on every built-in synth patch, one file each.
#
# The point is to be able to hear what the oscillators and the filter actually
# do, without a whole track around them. `PATCH=acid` for one; `HZ=` to move the
# chord.
def synth_audition!
  wanted = ENV["PATCH"].to_s.strip
  patches = wanted.empty? ? AnalogSynth::PATCHES.keys : [wanted.to_sym]
  root = (ENV["HZ"] || 130.81).to_f
  # A minor seventh, which shows a filter's character better than a single note:
  # four voices beating against each other is where detune becomes audible.
  chord = [1.0, 1.1892, 1.4983, 1.7818].map { |r| root * r }
  dir = File.join(ROOT, "scratch", "synth")

  patches.each do |patch|
    unless AnalogSynth::PATCHES.key?(patch)
      warn "no patch #{patch.inspect} — have: #{AnalogSynth::PATCHES.keys.join(', ')}"
      next
    end

    notes = chord.map { |hz| { hz:, at: 0.05, held: 1.8, gain: 0.7 } }
    out = AnalogSynth.render!(notes, dest: File.join(dir, "#{patch}.wav"), patch:,
                              duration: 3.4, seed: stable_hash(patch.to_s))
    puts out ? "  #{patch.to_s.ljust(14)} #{out.sub("#{ROOT}/", '')}" : "  #{patch}: produced silence"
  end
end

# The progression played on real oscillators.
#
# Every other pad in this engine is FluidSynth reading a soundfont: a recording
# of a sound somebody else made, which can be equalised afterwards and not much
# else. lib/analog_synth.rb is the other thing -- oscillators, a four-pole
# resonant ladder, and envelopes, which is what an analogue synthesiser is. It
# was built and measured and then left unwired, because connecting it as THE pad
# source means touching every patch table in the engine.
#
# This is the smaller version of that, and it is the version worth having: it
# renders the same chords as a SECOND pad, underneath the sampled one. Two
# instruments playing the same harmony is not a compromise, it is how a record
# gets depth -- the soundfont has the detail of a real instrument and this has
# the movement a recording cannot have, because its filter opens on every chord.
#
# warm_pad is the patch: two detuned saws and a square an octave down, filter
# opening over a second and a half, so the chord arrives rather than starts.
def analog_pad_file(pads, cfg, n_bars, beat_p)
  return nil if pads.nil? || pads.empty? || ENV["ANALOG_PAD"] == "0"

  bar = beat_p * 4.0
  chord_bars = [cfg[:chord_bars] || 2, 1].max
  # Held for its full length plus a little, so consecutive chords overlap the
  # way a hand does not lift between them.
  hold = (bar * chord_bars) * 1.04
  notes = []
  n_bars.times do |b|
    next unless (b % chord_bars).zero?

    chord = pads[(b / chord_bars) % pads.length]
    Array(chord[:hz]).each do |hz|
      next unless hz.to_f.positive?

      notes << { hz: hz.to_f, at: (b * bar).round(4), held: hold.round(4), gain: 0.55 }
    end
  end
  return nil if notes.empty?

  AnalogSynth.render!(notes, dest: dilla_render_tmp("analogpad"),
                      patch: ENV.fetch("ANALOG_PAD_PATCH", "warm_pad").to_sym,
                      duration: (n_bars * bar) + 2.0,
                      seed: stable_hash("analogpad:#{cfg[:track]}"))
end

# The records this flip may cut from: its own, plus one other.
#
# A track built from a single record can only say one thing. The second is
# chosen by the track name rather than at random, so a given track always digs
# in the same crate -- and it is deliberately NOT the neighbouring chop, which
# would come from the same few minutes of the same broadcast and sound like more
# of the first record rather than like a second one.
#
# The arranging step does not care which record a piece came from. It asks only
# what pitch the piece is, so pieces from two records sort themselves into one
# line: a horn from one answers a piano from the other because they are a third
# apart, not because anyone planned it.
def flip_sources(entry, cfg)
  return [entry[:path]] if ENV["FLIP_RECORDS"].to_s == "1"

  others = chopped_bed_paths.reject { |p| p == entry[:path] }
  return [entry[:path]] if others.empty?

  [entry[:path], others[stable_hash("crate:#{cfg[:track]}") % others.length]]
end

def chopped_bed_paths
  @chopped_bed_paths ||= Dir[File.join(ROOT, "samples", "chopped", "*", "loop.wav")].sort
end

# The progression as bare note-classes -- C is 0, C sharp is 1, and so on.
#
# The flip does not need to know a chord's name, its voicing, or which octave
# it sits in. It needs to know which notes are in it, so it can pick a piece of
# record whose pitch is one of them.
def chord_pitch_classes(pads)
  return [] if pads.nil? || pads.empty?

  pads.filter_map do |chord|
    classes = Array(chord[:hz]).filter_map { |hz| hz.to_f.positive? ? hz_to_pitch_class(hz) : nil }.uniq
    classes.empty? ? nil : classes
  end
end

def sidechain_filter_chain(cfg, drum_label: "[drums]")
  return wonky_sidechain_filters(drum_label:) unless cfg[:style_family] == :dilla

  if ENV.fetch("SIDECHAIN_STYLE", "dilla").to_s == "wonky"
    wonky_sidechain_filters(drum_label:)
  else
    dilla_sidechain_filters(drum_label:)
  end
end

DILLA_ROLE_VELOCITY_BASE = {
  kick_anchor: 0.56, kick_sync: 0.44, snare_back: 0.66, snare_off: 0.48,
  ghost: 0.30, hat_down: 0.50, hat_up: 0.40, open: 0.32, clap: 0.42
}.freeze

def dilla_role_velocity(role, bar, step, sec_gain: 1.0, backbeat: false)
  base = case role
         when :kick_anchor then DILLA_ROLE_VELOCITY_BASE[:kick_anchor]
         when :kick_sync then DILLA_ROLE_VELOCITY_BASE[:kick_sync]
         when :snare then backbeat ? DILLA_ROLE_VELOCITY_BASE[:snare_back] : DILLA_ROLE_VELOCITY_BASE[:snare_off]
         when :ghost then DILLA_ROLE_VELOCITY_BASE[:ghost]
         when :hat_down then DILLA_ROLE_VELOCITY_BASE[:hat_down]
         when :hat_up then DILLA_ROLE_VELOCITY_BASE[:hat_up]
         when :open then DILLA_ROLE_VELOCITY_BASE[:open]
         when :clap then DILLA_ROLE_VELOCITY_BASE[:clap]
         else 0.4
         end
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    perf = @composition_session.performer_profile
    if role == :ghost
      nudge = (ENV["GHOST_BOOST_NUDGE"] || "0").to_f
      base *= (perf[:ghost_boost] + nudge).clamp(0.75, 1.65)
    end
  end
  # Ghost notes were narrower than every other role (0.06 vs 0.08) --
  # backwards from real finger-drumming, where ghost hits are the LEAST
  # consistent dynamically (near-inaudible to clearly-present within the
  # same phrase), not the most locked-in.
  spread = role == :ghost ? 0.22 : 0.08
  vel = dilla_velocity(base, bar, step, spread:) * sec_gain
  # Wonky primary: kick-forward; snares/hats sit under kick (tops were piercing).
  if wonky_primary_drums?
    mul = case role
          when :kick_anchor, :kick_sync then 1.4
          when :snare, :clap then 1.05
          when :hat_down, :hat_up, :open then 0.88
          when :rim, :ghost then 0.75
          else 1.0
          end
    vel = (vel * mul).clamp(0.05, 0.95)
  end
  vel
end

def spectral_arp_chop_bar?(bar, chord_bars, drums_only, section)
  ENV["SPECTRAL_ARP"] == "1" && !drums_only && (bar % [chord_bars, 4].max).zero? &&
    !%i[breakdown intro].include?(section)
end
