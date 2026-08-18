# frozen_string_literal: true
#
# The hate/techno renderers and their harmony.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.


# =============================================================================
# TECHNO SYNTH (techno_hate.rb) — acid-industrial hybrid at 142 BPM
# =============================================================================

# --- Industrial techno, HATE-podcast shape ----------------------------------
#
# The existing render_techno is a good 8-bar loop and nothing else. Every one of
# its patterns is wrapped in mod(t, cycle), so a 213-bar render is that loop
# repeated 26 times, byte for byte. Hypnotic repetition is right for the genre;
# 26 identical repetitions is not an arrangement.
#
# What the style actually asks for, from the sources rather than from taste:
#
#   130-150 BPM, aggressive distorted sound design, heavy basslines.
#   Metallic clangs, hydraulic hisses and processed factory recordings layered
#   with heavy kicks. Heavy compression to make the kick punch, plus distortion
#   or bit-crushing for grit. Dark atmospheres and MINIMAL melodic content, so
#   the focus stays on energy. Reverb and delay for space and tension.
#   Repetitive, hypnotic structures with EVOLVING LAYERS.
#
# The last line is the one render_techno misses, and it is the difference
# between a loop and a set. So the core patterns keep their mod(t, cycle) --
# that is the hypnosis -- and each LAYER gets a gate on absolute time. The same
# eight bars come round and round while what is playing over them changes.
#
# A mix series like this runs long and moves in blocks rather than verses, so
# the schedule is in 16-bar blocks and reads as a set list rather than a song
# form: things arrive, sit, and leave.
HATE_BPM = (ENV["HATE_BPM"] || 145).to_f
HATE_CYCLE_BARS = 8
HATE_BLOCK_BARS = 16

# Which blocks each layer is present for, as a lambda over the block index.
# Deliberately written as rules rather than a table: a set that runs eight
# minutes or twenty should thin and thicken the same way either way.
HATE_LAYERS = {
  # Fifteen layers, each with its own arrival. The rules are written over the
  # block index rather than as a table so a set of eight minutes and one of
  # thirty thin and thicken the same way -- a mix series runs to whatever
  # length it runs to, and the shape should not be pinned to one duration.
  # Each lambda takes (position, block): position runs 0.0 to 1.0 across the
  # whole set, block is the raw index for the rules that want alternation.
  drone: ->(_p, _b) { true },                       # the bed is there before anything else
  hiss:  ->(_p, _b) { true },
  hat:   ->(_p, _b) { true },
  kick:  ->(p, _b) { p >= 0.08 && !p.between?(0.42, 0.5) },   # the room hears the drone first
  sub:   ->(p, _b) { p >= 0.15 && !p.between?(0.42, 0.5) },
  ghost: ->(p, _b) { p >= 0.25 && !p.between?(0.42, 0.5) },   # ghosts once the kick is established
  clap:  ->(p, _b) { p >= 0.15 && !p.between?(0.55, 0.62) },
  open:  ->(p, _b) { p >= 0.25 },
  metal: ->(p, _b) { p >= 0.3 },                    # the factory arrives late
  dfam:  ->(p, _b) { p >= 0.35 && !p.between?(0.55, 0.62) },  # the machine in the room
  poly:  ->(p, _b) { p >= 0.4 },                    # the 11-against-16 hat, deep in
  acid:  ->(p, _b) { p >= 0.45 },                   # the only sustained melodic content
  # Texture where the melody is not. paulwash is a bed, so it arrives early and
  # never leaves; weird is a spice and stays intermittent, because a signal with
  # no pitch left in it stops being interesting once you have placed it.
  paulwash: ->(p, _b) { p >= 0.12 },
  weird:    ->(p, b) { p >= 0.3 && b.odd? },
  bleep: ->(p, b) { p >= 0.45 && b.even? },         # blips answer the kit, in alternate blocks
  tom:   ->(p, b) { p >= 0.5 && b.odd? },
  bloop: ->(p, b) { p >= 0.55 && b.odd? },          # ...and the falling ones answer the bleeps
  ride:  ->(p, _b) { p >= 0.6 },
  # The sampled record, when TECHNO_HARMONY has put one under the arrangement.
  # It enters with the drone rather than late: the point of a bed is that the
  # rest of the arrangement is built over it, and a record that arrives at 45%
  # reads as a sample drop rather than as the floor of the track. It steps out
  # once across the middle so the return has somewhere to land.
  bed:   ->(p, _b) { !p.between?(0.42, 0.52) }
}.freeze

# One gate expression per layer, over absolute time: the union of the blocks it
# plays in. Layers present throughout return "1" and cost nothing.
# The schedule is expressed as a POSITION through the set, not a block number.
#
# Written against absolute block indices it only worked at one length. A
# two-minute render is five blocks, so every layer scheduled from block 5
# onwards -- toms, ride, and the acid line that carries the only melody --
# never played at all, and hate_gate returned an empty string, which ffmpeg
# rejects with "undefined constant or missing '(' in ''". A silent layer and a
# broken filter, from the same cause.
#
# Position is 0.0 at the first block and 1.0 at the last, so a set thins and
# thickens the same way whether it runs eight minutes or thirty.
# Where this block sits in the set, 0.0 to 1.0.
#
# HATE_PHASE shifts the whole window so a streamed set can pick up where the
# last block left off instead of replaying its own intro every few minutes. A
# render with no phase set behaves exactly as before.
def hate_position(block, blocks)
  # Position decides which of the eighteen layers have arrived. At 0.0 three
  # have -- drone, hiss and hat, the ambient ones -- and a block rendered there
  # measures -50.5 dB against a full block's -14.3.
  #
  # HATE_ARRIVED plays every block fully arrived, for a caller rendering a
  # sample rather than a set. A short render cannot express the arc: blocks are
  # its only resolution, so two blocks means positions 0.0 and 1.0 and nothing
  # between, and the first half of the piece is the three ambient layers alone.
  # That is right for the opening of a sixteen-minute set and wrong for a demo
  # slot, where it is half of everything the listener hears.
  return 1.0 if ENV["HATE_ARRIVED"] == "1"

  # One block is the whole set, so its place in the arc is the end of it rather
  # than the start -- otherwise it renders the way in and nothing else.
  base = blocks < 2 ? 1.0 : block.to_f / (blocks - 1)
  # Presence, not value. Guarding on `phase.zero?` made the FIRST streamed block
  # -- the one that should open the set at position 0 -- fall through to the
  # unphased branch and land mid-arc, so a stream started at its own midpoint
  # and then jumped backwards for block 1.
  raw = ENV["HATE_PHASE"]
  return base if raw.nil? || raw.empty?

  phase = raw.to_i
  arc = ENV.fetch("STREAM_TECHNO_ARC", "6").to_i.clamp(2, 40)
  # Each streamed block covers one slice of the arc, so consecutive blocks walk
  # forward through it and wrap rather than jumping back to nothing.
  ((phase + base) / arc).clamp(0.0, 1.0)
end

# This is the engine's SECOND arrangement.
#
# dilla_drums.rb has SECTION_LAYER_GAIN and section_layer_windows: named
# sections, a gain per layer per section, contiguous bars merged into windows,
# a short edge fade. This does the same job -- which layers sound when -- from
# a different vocabulary (blocks and an arc position rather than sections and
# bars) and emits a different filter (an `enable` expression built from
# `between` terms rather than a chain of `volume` stages).
#
# Both are good. Neither knows the other exists, which is the fork the genre
# work is supposed to be closing: `techno_bed_part!` above is the same story for
# the sampled bed, a second implementation of what build_sample_loop_filter
# does. The measurable form is in test_genre_renderers_reach_of_the_shared_spine,
# which records what each renderer reaches and fails if any of them reaches
# less. Merging the two arrangements is a real change to how every techno set
# sounds and is not something to do quietly at the end of a refactor -- but the
# duplication is now written down where the next person will find it, rather
# than being discoverable only by reading both renderers side by side.
def hate_gate(layer, blocks, bar_p)
  on = (0...blocks).select { |b| HATE_LAYERS.fetch(layer).call(hate_position(b, blocks), b) }
  return "1" if on.length == blocks
  # Never empty: a layer that plays nowhere is silence, and silence is "0".
  return "0" if on.empty?

  spans = on.chunk_while { |a, b| b == a + 1 }.map { |run| [run.first, run.last + 1] }
  spans.map { |from, to|
    "between(t,#{(from * HATE_BLOCK_BARS * bar_p).round(3)},#{(to * HATE_BLOCK_BARS * bar_p).round(3)})"
  }.join("+")
end

# Genre as a parameter rather than a fork.
#
# This renderer had no harmony in it at all. Its pitched layers carried literal
# frequencies -- an eight-entry acid_notes table, a 41 Hz sub, a drone on
# 36.71/36.95 -- and it referenced chord, scale, root, note_hz and midi_to_hz
# exactly zero times. That is why techno could sit next to the rest of the
# catalogue but never blend with it: there was nothing for a progression to
# attach to, so a jazz or soul progression could not drive an acid line and a
# techno slot could not share a key with the track beside it.
#
# These read the same progression render_dilla does -- dilla_resolve_config then
# dilla_progression -- and fold each chord's root into the register the layer
# already worked in, so the shape of the part is unchanged and only its pitches
# follow the harmony.
#
# Off by default. It changes what every techno render sounds like, which is the
# operator's ear to decide, not a wiring question: TECHNO_HARMONY=1.
TECHNO_ACID_REGISTER = (48.0..98.0).freeze
TECHNO_SUB_REGISTER = (32.0..64.0).freeze
TECHNO_DRONE_REGISTER = (30.0..58.0).freeze

# Octave-fold rather than clamp. A root outside the register is the right pitch
# class in the wrong octave, and clamping would flatten several chords onto the
# same boundary note -- which is how a progression turns into a drone.
def techno_fold(hz, register)
  h = hz.to_f
  return nil unless h.positive?

  h *= 2.0 while h < register.begin
  h /= 2.0 while h > register.end
  h.round(2)
end

# GENRE_HARMONY is the name for the property; TECHNO_HARMONY is kept because it
# shipped first and is what the techno A/B renders were made under. Both mean
# the same thing: the genre renderers take their pitches from the progression
# instead of from literals.
def genre_harmony_enabled? = ENV["GENRE_HARMONY"] == "1" || ENV["TECHNO_HARMONY"] == "1"

def techno_harmony_enabled? = genre_harmony_enabled?

TECHNO_BED_VOL = (ENV["TECHNO_BED_VOL"] || "0.55").to_f.clamp(0.0, 2.0)

# Fold the tempo ratio into three-quarter-to-three-halves rather than stretching
# whatever the arithmetic gives.
#
# A 92 BPM record against 145 BPM techno is 1.576x, which is not a stretch, it
# is a sprint -- and build_sample_loop_filter's own clamp stops at 2.0, so it
# would allow it. Halving it puts the record at half-time under the kit (0.788x,
# a 21% slow-down), which is what a DJ does with the same two tempos and what
# the material can actually take.
def techno_bed_ratio(loop_bpm)
  r = loop_bpm.to_f.positive? ? (HATE_BPM / loop_bpm.to_f) : 1.0
  r /= 2.0 while r > 1.5
  r *= 2.0 while r < 0.75
  r.round(5)
end

# atempo, not asetrate.
#
# The engine's usual sample path varispeeds -- asetrate, which moves pitch and
# tempo together like a turntable. That is right when the pads are transposed to
# the loop, which is what render_dilla does. Here it would be backwards: the
# acid, sub and drone have just been tuned TO the progression, and varispeeding
# the record by 21% would move it a third of an octave away from the harmony it
# is supposed to be sharing. Preserving pitch is what keeps the two in one key.
def techno_bed_part!(work, cycle)
  return nil unless techno_harmony_enabled?

  entry = sample_loop_for(ENV["TRACK"])
  return nil unless entry.is_a?(Hash) && entry[:path] && File.file?(entry[:path].to_s)

  ratio = techno_bed_ratio(entry[:bpm])
  chain = [
    ("atempo=#{ratio}" unless (ratio - 1.0).abs < 0.001),
    "highpass=f=#{(entry[:hp] || 45).to_i}",
    ("equalizer=f=90:t=o:w=1.1:g=#{entry[:sub_db].to_f}" unless entry[:sub_db].to_f.zero?),
    "lowpass=f=#{(entry[:lp] || 6000).to_i}",
    "volume=#{TECHNO_BED_VOL}",
  ].compact.join(",")
  path = File.join(work, "bed.wav")
  sh! "ffmpeg", "-y", "-v", "error", "-stream_loop", "-1", "-i", entry[:path].to_s,
      "-t", cycle.to_s, "-af", "aformat=channel_layouts=stereo,#{chain}",
      "-c:a", "pcm_s16le", path
  return nil unless File.file?(path) && File.size(path) > 10_000

  dmesg("techno bed #{File.basename(entry[:path])} @#{entry[:bpm].to_f.round}bpm " \
        "-> #{(entry[:bpm].to_f * ratio).round}bpm (atempo #{ratio}, pitch held)",
        unit: "techno0", parent: "dilla0")
  path
end

# One root per bar of the cycle, or nil when the harmonic path is off or the
# progression will not resolve. nil means "keep the literal tables", so a broken
# or missing progression degrades to exactly today's sound rather than to
# silence.
# The chord's NAME, not its lowest note.
#
# enrich_progression voices a good deal of this catalogue rootless -- that is
# the point of a rootless voicing -- so the lowest frequency in c[:hz] is
# routinely the third or the seventh. Following it would put the acid line a
# third above the harmony on exactly the chords that were voiced most carefully,
# and it would read as wrong without reading as broken. The name carries the
# root whatever the voicing did with it; hz.min is the fallback for the handful
# of generated chords whose names are not note-spelled ("napl3maj7", "bk2m9").
def techno_chord_root_hz(chord)
  name = chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "")
  if (m = name.match(/\A([A-G][#b]?)/i))
    pc = DillaLofiMachine::NOTE_PC[m[1][0].upcase + m[1][1..].to_s.downcase]
    return 55.0 * (2.0**(((pc - 9) % 12) / 12.0)) if pc
  end
  Array(chord[:hz]).min.to_f
end

def techno_harmony_roots(bars, register: TECHNO_ACID_REGISTER)
  return nil unless techno_harmony_enabled?

  cfg = dilla_resolve_config
  pads = dilla_progression(cfg[:progression])
  roots = Array(pads).filter_map { |c| techno_chord_root_hz(c) if c.is_a?(Hash) }
                     .select(&:positive?)
  return nil if roots.length < 2

  Array.new(bars) { |b| techno_fold(roots[b % roots.length], register) }.compact
rescue StandardError => e
  dmesg_warn("techno harmony unavailable (#{e.message}), using the literal tables")
  nil
end

# One switch that forbids every pitched layer, rather than four that each
# forbid one.
#
# This exists because "no leads" took six rounds to actually achieve. Each
# attempt turned off the layer that had been named -- acid, then bleep and
# bloop, then dfam -- and the next render still had a pitched line in it,
# because the renderer has more tonal layers than anyone remembers. The list is
# acid, bleep, bloop (chirps on a per-bar note table), dfam (an 8-step PITCH
# sequence through a resonant filter), and the drone.
#
# HATE_TONAL=0 turns off all of them at once. It is a floor, not a default: the
# individual switches still work, and setting this cannot accidentally enable
# anything. test_hate_tonal_zero_silences_every_pitched_layer is the gate.
HATE_TONAL_LAYERS = %w[HATE_MELODY HATE_DFAM HATE_DRONE].freeze

def hate_forbid_tonal!
  return false if ENV.fetch("HATE_TONAL", "1") != "0"

  HATE_TONAL_LAYERS.each { |k| ENV[k] = "0" }
  true
end

def render_hate_techno(destination = File.join(ROOT, "renders", "hate_session.mp3"))
  require_tools! "ffmpeg"
  if hate_forbid_tonal!
    dmesg("HATE_TONAL=0 — melody, dfam and drone all off", unit: "techno0", parent: "dilla0")
  end
# The floor is what a render is allowed to ask for, not what it is allowed to
# sound like. Those were confused here for a long time, at real cost.
#
# demo-all asks for 0.33 minutes -- the length of the hip-hop slot beside it,
# so the two sit side by side rather than one running twice the other. Below
# half a minute this renderer used to answer with near-silence, so the floor
# was raised to 0.5 to stop it. Measured through this method, overall RMS:
#
#   HATE_MIN 0.33  ->  -47.7 dB, 26.5s   near-silent, low end at -79.4
#   HATE_MIN 0.50  ->  -13.8 dB, 53.0s   healthy overall
#   HATE_MIN 1.00  ->  -15.6 dB, 79.4s   healthy
#
# Overall RMS is the wrong instrument and 0.50 is the proof. It renders two
# blocks: the near-silent one, then a full one. Per block that is -50.5 dB
# then -14.3, and the average of those is -14.3 -- so the row above reads
# healthy while half the file is inaudible. Every techno slot in the demo has
# this shape, identical to 0.1 dB across all 27, because the dead half carries
# no progression: at position 0.0 only drone, hiss and hat have arrived.
#
# The cause was never the requested length. It is hate_position returning 0.0
# for a single block, which is fixed where it lives, so the floor no longer
# has to stand in for it: one block now renders fully arrived at -14.6 dB
# across its whole 26.5s. Measure per block, not overall, before changing
# either number -- the failure is silent and does not raise.
  minutes = (ENV["HATE_MIN"] || 16).to_f.clamp(0.1, 60.0)
  beat = 60.0 / HATE_BPM
  bar = beat * 4
  step = beat / 4
  tick = beat / MPC_PPQ
  cycle = (bar * HATE_CYCLE_BARS).round(6)
  # ...and the block floor is the second half of the same fault. With the clamp
  # fixed, 0.33 minutes asks for one block; max(.., 2) doubled it back to 53s.
  # Two blocks is right for a standalone session, where one 16-bar block is not a
  # techno track. It is wrong for a demo slot, which is a sample and not a set,
  # so the floor is a knob and demo-all sets it to 1.
  min_blocks = (ENV["HATE_MIN_BLOCKS"] || 2).to_i.clamp(1, 64)
  blocks = [(minutes * 60.0 / (bar * HATE_BLOCK_BARS)).ceil, min_blocks].max
  total = (blocks * HATE_BLOCK_BARS * bar).round(3)

  # One cycle per layer, then loop it. aeval evaluates per SAMPLE, so
  # synthesising 16 minutes directly meant tens of millions of evaluations of a
  # thirty-term expression per layer -- measured at roughly a two-hour render.
  # Each layer is built once over its eight-bar cycle instead, then looped and
  # gated. That is also how the music is actually made.

  # Dilla's pocket, on a machine grid.
  #
  # This is the fusion the engine is uniquely placed to attempt and the reason
  # the request said "use the best from Dilla". Industrial techno is quantised
  # by definition -- that rigidity is the genre. GROOVE_FEELS holds the tick
  # offsets that make an MPC lurch instead of march: on dilla_drag the snare
  # sits 4 ticks late while the hats hold the grid, so the top and the backbeat
  # disagree by about 28ms at this tempo.
  #
  # Applied here at reduced depth. A full drag at 145 BPM stops reading as a
  # pocket and starts reading as a timing error, because the bar is 40% shorter
  # than the 88 BPM these offsets were measured at. Two thirds keeps the lurch
  # and stays danceable. HATE_DILLA=0 renders it dead straight.
  feel = DillaGroove::GROOVE_FEELS[:dilla_drag]
  depth = ENV.fetch("HATE_DILLA", "1") == "0" ? 0.0 : ENV.fetch("HATE_DILLA_DEPTH", "0.66").to_f
  drag = ->(role) { ((feel[role] || 0) * depth * tick).round(6) }

  # Resolved once, up here, because three layers want it and they are built in
  # source order -- sub before acid before drone. Assigning it beside the acid
  # table left sub referencing a variable that did not exist yet, which Ruby
  # reports as a NameError at render time rather than at load.
  harmony_roots = techno_harmony_roots(HATE_CYCLE_BARS)
  if harmony_roots
    dmesg("techno harmony: #{harmony_roots.uniq.length} chord root(s) " \
          "#{harmony_roots.first(4).map { |h| h.round(1) }.join('/')}",
          unit: "techno0", parent: "dilla0")
  end

  kick_per_bar = Array.new(HATE_CYCLE_BARS) { [0, 4, 8, 12] }
  kick_per_bar[7] = [0, 4, 8, 12, 14, 15]
  ghost_per_bar = Array.new(HATE_CYCLE_BARS) { [7, 11] }        # Dilla's ghost hits
  ghost_per_bar[3] = [3, 7, 11, 15]
  clap_per_bar = Array.new(HATE_CYCLE_BARS) { [4, 12] }
  clap_per_bar[7] = [4, 12, 14]
  hat_per_bar = Array.new(HATE_CYCLE_BARS) { [2, 6, 10, 14] }
  hat_per_bar[3] = []
  hat_per_bar[5] = (0..15).step(2).to_a
  open_per_bar = Array.new(HATE_CYCLE_BARS) { [] }
  open_per_bar[3] = [14]; open_per_bar[7] = [14]
  ride_per_bar = Array.new(HATE_CYCLE_BARS) { [0, 8] }
  metal_per_bar = Array.new(HATE_CYCLE_BARS) { [] }
  metal_per_bar[1] = [7]; metal_per_bar[2] = [3, 11]; metal_per_bar[4] = [7, 13]; metal_per_bar[6] = [5]
  tom_per_bar = Array.new(HATE_CYCLE_BARS) { [] }
  tom_per_bar[5] = [9, 13]; tom_per_bar[7] = [6, 10]

  # HATE_MODERN=1 is the contemporary club pattern, not the industrial one.
  #
  # Modern techno is defined by a very small number of things and the offbeat
  # open hat is the biggest: a four-on-the-floor kick with an open hat on every
  # eighth between the kicks. That single relationship is what makes a pattern
  # read as current rather than as 90s industrial, and it is why this is a
  # separate mode from HATE_INTRICATE rather than more of it.
  #
  # The rest follows from it: closed hats on straight sixteenths to fill under
  # the opens, a clap on 2 and 4 only, ghosts pulled right back because the
  # groove is meant to be driving rather than shuffled, and toms and metal
  # almost absent -- modern techno is sparse in the mids, and its weight comes
  # from the kick and the sub rather than from the number of parts.
  if ENV.fetch("HATE_MODERN", "0") != "0"
    HATE_CYCLE_BARS.times do |b|
      kick_per_bar[b] = [0, 4, 8, 12]                       # four on the floor, no variations
      open_per_bar[b] = [2, 6, 10, 14]                      # THE offbeat open hat
      hat_per_bar[b] = (0..15).step(2).to_a                  # eighths under the opens
      clap_per_bar[b] = [4, 12]                              # 2 and 4, nothing else
      ghost_per_bar[b] = b.odd? ? [7] : []                   # barely there
      ride_per_bar[b] = []
      metal_per_bar[b] = (b % 4).zero? ? [14] : []           # one accent per four bars
      tom_per_bar[b] = []
    end
    # One dropped kick every eight bars is the only variation the pattern gets.
    kick_per_bar[7] = [0, 4, 8]
  end

  # HATE_INTRICATE=1 thickens the programming without speeding it up.
  #
  # The tables above are deliberately sparse -- four kicks, two ghosts, four
  # hats, and whole bars with nothing on them. That is the right density for a
  # hypnotic set and the wrong one when the request is "much more intricate".
  #
  # Intricacy here means MORE PLACES, not more speed: sixteenth hats with gaps
  # rather than a straight run, ghosts on the odd sixteenths where a shuffle
  # lives, kick variations that differ per bar so the loop never repeats
  # exactly, toms and metal answering across bars, and rides on the offbeat.
  # Every added hit still lands on the same grid the drag is applied to, so the
  # pocket is unchanged -- it is busier, not straighter.
  if ENV.fetch("HATE_INTRICATE", "0") != "0"
    HATE_CYCLE_BARS.times do |b|
      # Kick: keep the four on the floor, add a syncopated push that moves per
      # bar so no two bars are identical.
      kick_per_bar[b] = ([0, 4, 8, 12] + [[14], [6], [3, 14], [10], [7], [2, 11], [15], [6, 14]][b % 8]).uniq.sort
      # Ghosts on odd sixteenths -- where a shuffle's ghost notes actually sit.
      ghost_per_bar[b] = ([3, 7, 11, 15] + (b.even? ? [5, 13] : [1, 9])).uniq.sort
      # Hats: eighths with holes punched in them, and the holes move.
      #
      # Sixteenths here was too much for the synthesis, not for the music: each
      # hit becomes another term in one aevalsrc expression, and 16 per bar over
      # 8 bars made ffmpeg fail the layer outright with "cannot allocate
      # memory". Eighths plus the offbeat ride below cover the same ground at
      # half the term count.
      holes = [[4], [0], [12], [8]][b % 4]
      hat_per_bar[b] = ((0..15).step(2).to_a - holes)
      # Open hat answering the clap, late in the bar.
      open_per_bar[b] = b.odd? ? [14] : [7]
      # Ride on the offbeat eighths rather than the downbeats.
      ride_per_bar[b] = [2, 6, 10, 14]
      # Metal and toms trade bars so something new arrives every two.
      metal_per_bar[b] = b.even? ? [5, 13] : [3, 9]
      tom_per_bar[b] = b.odd? ? [6, 10, 14] : [9]
    end
    # Claps keep the backbeat and gain a flam on the turnaround.
    clap_per_bar[3] = [4, 12, 13]
    clap_per_bar[7] = [4, 12, 14, 15]
  end

  # A hat line on an 11-step cycle against a 16-step bar, so it only meets the
  # downbeat every 11 bars. This is the polymeter facility built earlier today;
  # its first use was a hi-hat in a hip-hop track, and it belongs here more --
  # the whole hypnotic quality of this genre is a pattern you cannot quite
  # count.
  poly_hits = (0...(HATE_CYCLE_BARS * 16)).select { |s| DillaGroove.polymeter_steps(s / 16, cycle: 11, pulses: 7).include?(s % 16) }

  at = ->(b, s, role = nil) { (((b * bar) + (s * step)) + (role ? drag.call(role) : 0)).round(6) }
  gather = lambda do |rows, role = nil|
    HATE_CYCLE_BARS.times.flat_map { |b| rows[b].map { |s| at.call(b, s, role) } }
  end
  env = lambda do |times, len, decay|
    return "0" if times.empty?

    times.map { |t| "between(t,#{t},#{(t + len).round(6)})*exp(-(t-#{t})*#{decay})" }.join("+")
  end

  work = scratch_path("hate")
  FileUtils.rm_rf(work)
  FileUtils.mkdir_p(work)
  parts = {}

  # The record goes in first so it is the floor the rest is built on, and so a
  # failure to prepare it costs the bed rather than the whole render.
  if (bed_path = techno_bed_part!(work, cycle))
    parts[:bed] = bed_path
  end

  # -af takes a linear chain; anything with named pads -- an asplit into a wet
  # branch and back -- is a graph and needs -filter_complex. Detected rather
  # than declared per call site, because getting it wrong fails the whole layer
  # and the error ffmpeg gives points at the expression, not at the flag.
  tone = lambda do |name, expr, chain|
    parts[name] = File.join(work, "#{name}.wav")
    src = ["-f", "lavfi", "-i", "aevalsrc='#{expr}':s=#{SAMPLE_RATE}:d=#{cycle}"]
    body = "aformat=channel_layouts=stereo,#{chain}"
    args = if chain.include?("[")
             ["-filter_complex", "[0:a]#{body}[o]", "-map", "[o]"]
           else
             ["-af", body]
           end
    sh! "ffmpeg", "-y", "-v", "error", *src, *args, "-c:a", "pcm_s16le", parts[name]
  end
  noise = lambda do |name, colour, times, len, decay, gain, chain|
    parts[name] = File.join(work, "#{name}.wav")
    if times.empty?
      sh!("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=#{SAMPLE_RATE}:cl=stereo:d=#{cycle}",
          "-c:a", "pcm_s16le", parts[name])
    else
      sh! "ffmpeg", "-y", "-v", "error", "-f", "lavfi",
          "-i", "anoisesrc=color=#{colour}:r=#{SAMPLE_RATE}:amplitude=0.9:d=#{cycle}:seed=#{noise_seed(41)}",
          "-af", "aformat=channel_layouts=stereo,volume='(#{env.call(times, len, decay)})*#{gain}':eval=frame,#{chain}",
          "-c:a", "pcm_s16le", parts[name]
    end
  end

  hit = ->(t, len, amp, decay, body) { "between(t,#{t},#{(t + len).round(6)})*#{amp}*exp(-(t-#{t})*#{decay})*#{body}" }

  # KICK. Grit before punch: bit-crush and saturate first, compress after.
  # Compressing a clean kick and distorting the result gives a loud clean kick,
  # which is not this genre. asubboost adds the sub the speaker cabinet would.
  tone.call(:kick,
            gather.call(kick_per_bar, :kick).map { |t|
              hit.call(t, 0.22, 0.98, 7, "sin(2*PI*(58*(t-#{t})+190*(t-#{t})*exp(-(t-#{t})*26)))")
            }.join("+"),
            "acrusher=bits=10:samples=1:mix=0.22," \
            "asoftclip=type=tanh:threshold=0.72:output=0.9:oversample=4," \
            "acompressor=threshold=-12dB:ratio=9:attack=1:release=38:makeup=4," \
            "asubboost=dry=0.9:wet=0.4:decay=0.6:feedback=0.5:cutoff=90," \
            "equalizer=f=58:t=o:w=0.8:g=5,lowpass=f=7000")

  # GHOST KICK. Dilla's ghosts, at a fifth of the level, nudged 2 ticks late so
  # they lean rather than land.
  tone.call(:ghost,
            gather.call(ghost_per_bar, :ghost).map { |t|
              hit.call(t, 0.1, 0.24, 16, "sin(2*PI*(64*(t-#{t})+120*(t-#{t})*exp(-(t-#{t})*30)))")
            }.join("+"),
            "asoftclip=type=atan:threshold=0.6:oversample=4,lowpass=f=2400,pan=stereo|c0=0.9*c0|c1=1.0*c1")

  # The sub takes the tonic rather than a per-bar root. A sub that moves with
  # every chord stops reading as the floor of the record and starts reading as a
  # bassline, which is a different instrument and not this one's job.
  sub_hz = (harmony_roots && techno_fold(harmony_roots.first, TECHNO_SUB_REGISTER)) || 41
  tone.call(:sub,
            gather.call(kick_per_bar, :kick).map { |t|
              hit.call(t, 0.42, 0.5, 4, "sin(2*PI*#{sub_hz}*(t-#{t}))")
            }.join("+"),
            "lowpass=f=90,virtualbass=cutoff=110:strength=0.6")

  # ACID. The only melodic content. Frequency-shifted rather than pitch-shifted
  # on the wet side -- afreqshift moves every partial by the same number of Hz
  # instead of the same ratio, so the harmonic series stops being harmonic and
  # the result reads as metal rather than as a note. That is the futurist trick
  # this style leans on and it has no analogue on a keyboard.
  acid_steps = [0, 6, 10, 14]
  # The literal table is the fallback, not the definition: with TECHNO_HARMONY=1
  # these become the progression's chord roots, one per bar of the cycle, folded
  # into the same register the table already sat in (A1 to G2).
  acid_notes = harmony_roots || [55.00, 55.00, 58.27, 55.00, 65.41, 55.00, 58.27, 51.91]
  # HATE_MELODY=0 drops it entirely. The acid IS the only melodic content here,
  # so with it off the piece is drums, drone and texture -- which is a real
  # setting for this genre, not a broken render.
  if ENV.fetch("HATE_MELODY", "1") != "0"
  tone.call(:acid,
            HATE_CYCLE_BARS.times.flat_map { |b|
              acid_steps.map { |s| hit.call(at.call(b, s), 0.16, 0.55, 11, "sin(2*PI*#{acid_notes[b]}*(t-#{at.call(b, s)}))") }
            }.join("+"),
            "asoftclip=type=tanh:threshold=0.35:output=0.85:oversample=4," \
            "asplit=2[ad][aw];" \
            "[aw]afreqshift=shift=63,volume=0.34[af];" \
            "[ad][af]amix=inputs=2:normalize=0," \
            "bandpass=f=520:w=760," \
            "aphaser=speed=0.12:decay=0.5:delay=2.6," \
            "aecho=0.7:0.55:#{(step * 3000).round}|#{(step * 6000).round}:0.4|0.22")
  end

  # PAULSTRETCH WASH. Texture where the melody was.
  #
  # Paulstretch's signature is not slowness, it is the absence of any transient:
  # magnitudes kept, phase thrown away, so a source becomes a cloud that has no
  # attack anywhere in it and no rhythm to read. There is no rubberband filter
  # in this ffmpeg and no paulstretch anywhere, but the effect does not need a
  # time-stretch when the source is synthesised -- write the sustain directly
  # and destroy the phase.
  #
  # Two windows rather than one. 8192 with 0.9 overlap is long enough that
  # everything inside it averages into a wash; 1024 underneath keeps a trace of
  # movement so the layer does not sit completely still for two minutes. The
  # slow pulsator pair beat against each other at 0.06 and 0.09 Hz, which is
  # under a cycle per ten seconds -- swell, not wobble.
  #
  # apulsator and not tremolo for those: tremolo's `f` floor is 0.1 Hz, and a
  # refused filter does not degrade quietly, it fails the whole chain and takes
  # the layer with it. Measured -- tremolo=f=0.06 killed paulwash outright with
  # "error applying option 'f' to filter 'tremolo': result too large".
  # apulsator accepts down to 0.01 Hz.
  if ENV.fetch("HATE_PAULSTRETCH", "1") != "0"
    pw_root = (harmony_roots&.first || 55.0) * 4
    pw = [pw_root, pw_root * 1.5, pw_root * (2**(10.0 / 12.0)), pw_root * 2].map { |h| h.round(2) }
    # win_size in SAMPLES here, but Paulstretch specifies its window in seconds
    # and wants it long: 0.25s upward, because a short window reads as grain and
    # a long one is what produces the slow spectral pad. 32768 at 44.1k is
    # 0.74s. The first attempt used 8192 (0.19s), which is the grainy end.
    pw_win = ENV.fetch("HATE_PAULSTRETCH_WIN", "32768").to_i
    # Phase must be RANDOM, not a function of the bin index. cos(b) is a fixed
    # pattern across bins -- deterministic, and it re-imposes a structure that
    # the whole point of this is to destroy. random(n) in ffmpeg's expression
    # evaluator returns [0,1) and advances its own state per call.
    scramble = "afftfilt=real='hypot(re,im)*cos(random(1)*6.2832)':" \
               "imag='hypot(re,im)*sin(random(2)*6.2832)':" \
               "win_size=#{pw_win}:overlap=0.9"
    # +26 dB of makeup, measured not guessed. Randomising phase makes partials
    # cancel instead of sum, and the chain was measured at 26.3 dB of loss
    # (-19.9 dB source -> -46.2 dB out). Without this the layer renders, reports
    # as a layer, and is inaudible in the mix -- the first version of this
    # nulled against the melody-less render at -46 dB, i.e. it did nothing.
    # Noise, not chord tones.
    #
    # The first version built this from root/5th/b7/octave and smeared those.
    # Smearing a chord does not stop it being a chord -- it is a sustained pad
    # playing the harmony, i.e. keys, which is exactly what was asked to go.
    # Paulstretch on NOISE has no pitch to hear at all: the magnitudes are
    # broadband, the phase is random, and what is left is air and movement.
    # Shaped by the bandpass below rather than by a note.
    tone.call(:paulwash,
              "0.25*(random(0)*2-1)",
              "#{scramble},#{scramble}," \
              "bandpass=f=900:width_type=h:width=1600," \
              "highpass=f=140,lowpass=f=6000," \
              "apulsator=hz=0.06:amount=0.45:offset_r=0.5," \
              "apulsator=hz=0.09:amount=0.25:offset_r=0.25," \
              "chorus=0.6:0.9:50|70|90:0.4|0.32|0.3:0.25|0.4|0.3:2|2.3|1.3," \
              "aphaser=speed=0.15:decay=0.55:delay=3.0," \
              "aecho=0.8:0.9:#{(step * 7000).round}|#{(step * 11000).round}:0.55|0.4," \
              "aecho=0.7:0.8:#{(step * 17000).round}|#{(step * 23000).round}:0.4|0.3," \
              "stereowiden=delay=32:feedback=0.5:crossfeed=0.4:drymix=0.6," \
              "volume=#{ENV.fetch('HATE_PAULSTRETCH_GAIN', '43')}dB")
  end

  # WEIRD. The deliberately wrong one.
  #
  # afreqshift moves every partial by the same NUMBER of Hz instead of the same
  # ratio, so the harmonic series stops being harmonic -- the same trick the
  # acid used on its wet side, but here it is the whole signal and the shift is
  # large enough that no pitch survives it. Then flanger and a phaser on top of
  # that, so what is left drifts. aphaser's speed floor is 0.1; below it the
  # filter refuses to configure and refusing one filter kills the entire chain,
  # so 0.12 is deliberate and not a rounding.
  if ENV.fetch("HATE_WEIRD", "1") != "0"
    w_root = (harmony_roots&.first || 55.0) * 2
    # Noise here too, for the same reason paulwash is noise: a shifted sine is
    # still a pitch, and the brief was no keys. The two slow AM terms stay --
    # they are what makes it breathe rather than sit -- but they now modulate
    # broadband noise instead of a note.
    tone.call(:weird,
              "0.2*(random(3)*2-1)*(0.5+0.5*sin(2*PI*0.7*t))*" \
              "(0.6+0.4*sin(2*PI*0.23*t))",
              "afreqshift=shift=#{(37 + (w_root % 23)).round}," \
              "flanger=delay=14:depth=8:regen=45:speed=0.13," \
              "aphaser=speed=0.12:decay=0.6:delay=3.2," \
              "asoftclip=type=tanh:threshold=0.4:output=0.7:oversample=4," \
              "bandpass=f=1400:width_type=h:width=2200," \
              "crystalizer=i=3," \
              "aecho=0.6:0.7:#{(step * 4500).round}|#{(step * 9000).round}:0.45|0.3," \
              "stereowiden=delay=18:feedback=0.4:crossfeed=0.3:drymix=0.7," \
              "volume=#{ENV.fetch('HATE_WEIRD_GAIN', '22')}dB")
  end

  # DRONE. A dark bed under everything, built from two detuned saws a beat
  # apart so it beats slowly against itself, then spectrally smeared.
  # Detune ratio preserved, not the literal pair. 36.95/36.71 is 1.00654, and it
  # is the ratio that makes the two saws beat slowly against each other -- moving
  # the drone to a new tonic has to carry that interval with it or the beating
  # either disappears or turns into a chord.
  drone_hz = (harmony_roots && techno_fold(harmony_roots.first, TECHNO_DRONE_REGISTER)) || 36.71
  drone_detuned = (drone_hz * 1.00654).round(2)
  # The drone had no switch of its own until now. It is two detuned saws on a
  # tonic -- pitched, however smeared -- so HATE_TONAL has to be able to reach
  # it or "no tonal layers" is not true.
  if ENV.fetch("HATE_DRONE", "1") != "0"
  tone.call(:drone,
            "0.13*(sin(2*PI*#{drone_hz}*t)+sin(2*PI*#{drone_detuned}*t)+" \
            "0.5*sin(2*PI*#{(drone_hz * 2).round(2)}*t))",
            # Phase randomised per bin while the magnitudes are kept: the
            # spectral smear that turns two detuned saws into a wash with no
            # attack anywhere in it. afftfilt works per BIN, not per sample --
            # its expressions have no `t`, which is what the first attempt at
            # this assumed and why the whole layer failed to configure.
            "afftfilt=real='hypot(re,im)*cos(b)':imag='hypot(re,im)*sin(b)':win_size=2048:overlap=0.8," \
            "lowpass=f=1200,tremolo=f=0.14:d=0.28,stereowiden=delay=22:feedback=0.4:crossfeed=0.35:drymix=0.7")
  end

  # DFAM. Dual-oscillator FM percussion on an 8-step pitch sequence.
  #
  # The Moog DFAM is a semi-modular percussion synth whose whole character is
  # that pitch and decay move per STEP -- one knob row for pitch, another for
  # velocity, eight steps each -- so a single voice walks through a phrase
  # instead of repeating one sound. That is what industrial techno is built out
  # of, and DfamEngine has held the semantics all along: dual-osc FM, noise
  # blend, resonant lowpass, per-step pitch and velocity.
  #
  # It was reachable only from render_dilla, where it sits under hip-hop drums.
  # Here it is the machine in the room.
  #
  # The sequence runs at 8 steps against the bar's 16, so it turns over twice a
  # bar and lands differently against the kick each time. Pitch 0-100 from the
  # engine maps onto 45-360 Hz: percussion register, not melody.
  dfam_patch = DfamEngine.resolve_patch
  dfam_pattern = DfamEngine.resolve_pattern(seed: (@render_seed || 0) + stable_hash("hate"))
  fm_index = dfam_patch[:fm_pct] / 100.0 * 6.0
  dfam_decay = 1000.0 / [dfam_patch[:decay_ms], 40].max
  dfam_sig = (0...(HATE_CYCLE_BARS * 2)).map do |i|
    idx = i % DfamEngine::STEPS
    t0 = ((i * bar) / 2.0).round(6)
    pitch = dfam_pattern[:pitch][idx]
    vel = dfam_pattern[:velocity][idx] / 100.0
    f1 = (45.0 + (pitch / 100.0 * 315.0)).round(2)
    f2 = (f1 * (dfam_patch[:osc2_hz].to_f / [dfam_patch[:osc1_hz], 1].max)).round(2)
    dt = "(t-#{t0})"
    body = "sin(2*PI*#{f1}*#{dt}+#{fm_index.round(3)}*sin(2*PI*#{f2}*#{dt}))"
    "between(t,#{t0},#{(t0 + 0.4).round(6)})*#{(0.42 * vel).round(3)}*exp(-#{dt}*#{dfam_decay.round(2)})*#{body}"
  end.join("+")
  # Its own gate, not HATE_MELODY's.
  #
  # It was briefly folded into HATE_MELODY because an 8-step PITCH sequence
  # through a resonant filter does read as a line. But this is the machine the
  # whole genre is built on and the operator wants it forward, so it gets
  # HATE_DFAM instead: melody off and DFAM heavy is a real combination, and one
  # switch could not express it.
  #
  # HATE_DFAM_HEAVY pushes it from an element to the loudest thing in the room:
  # the resonance goes up, the softclip becomes drive rather than polish, a
  # bitcrusher takes the edges off the sample rate, and the echo gets long
  # enough to blur into the next hit.
  if ENV.fetch("HATE_DFAM", "1") != "0"
  heavy = ENV.fetch("HATE_DFAM_HEAVY", "0") != "0"
  dfam_res = (dfam_patch[:res_pct] / 100.0 * (heavy ? 14 : 8) + 0.7).round(2)
  dfam_tail = if heavy
                "acrusher=bits=9:samples=2:mix=0.35," \
                "afreqshift=shift=27," \
                "aecho=0.8:0.7:#{(step * 2000).round}|#{(step * 4000).round}|#{(step * 7000).round}:0.5|0.32|0.18," \
                "aphaser=speed=0.22:decay=0.5:delay=2.4," \
                "stereotools=slev=1.8,volume=7dB"
              else
                "aecho=0.7:0.5:95|185:0.3|0.17,stereotools=slev=1.4"
              end
  tone.call(:dfam, dfam_sig,
            # The resonant lowpass is the other half of the instrument: a
            # 12dB/oct sweep with the resonance up, which is what gives a DFAM
            # hit its pitched ring rather than a flat thud.
            "lowpass=f=#{dfam_patch[:filter_hz]}:width_type=q:width=#{dfam_res}," \
            "asoftclip=type=atan:threshold=#{heavy ? '0.32' : '0.55'}:output=#{heavy ? '1.0' : '0.9'}:oversample=4," \
            "#{dfam_tail}")
  end

  # Long chains on the drums.
  #
  # Each of these was three or four stages: shape it, echo it, place it. Written
  # out as arrays because at eight or nine stages a single string stops being
  # readable, and the order matters more than any individual value -- saturate
  # before you compress and you get grit, after and you get a loud clean hit.
  #
  # The shape of each chain is the same: BAND (what part of the noise this drum
  # is) -> DAMAGE (crush, saturate, frequency-shift) -> MOVEMENT (phaser,
  # flanger, tremolo, so it is never twice the same) -> SPACE (echo, then
  # placement). Damage before movement, because modulating a clean signal sounds
  # like an effect and modulating a broken one sounds like a machine.
  drum_chain = ->(stages) { stages.compact.join(",") }

  noise.call(:clap, "white", gather.call(clap_per_bar, :snare), 0.05, 34, 0.55,
             drum_chain.call([
               "bandpass=f=1600:w=2200",
               "acrusher=bits=12:samples=2:mix=0.3",
               "asoftclip=type=atan:threshold=0.6:output=0.9:oversample=4",
               "flanger=delay=2:depth=3:regen=40:speed=0.3",
               "adynamicequalizer=dfrequency=1800:tfrequency=1800:threshold=0.1:ratio=4",
               "aecho=0.6:0.45:37|74|151:0.28|0.18|0.09",
               "haas=level_in=1:level_out=1:side_gain=0.8:left_delay=2.6:right_delay=4.1",
               "stereotools=slev=1.3",
             ]))

  noise.call(:hat, "white", gather.call(hat_per_bar, :hat), 0.035, 80, 0.32,
             drum_chain.call([
               "highpass=f=8500",
               "acrusher=bits=9:samples=1:mix=0.22",
               "aphaseshift=shift=0.25",
               "tremolo=f=7.3:d=0.22",
               "aecho=0.5:0.3:29|61:0.2|0.1",
               "pan=stereo|c0=0.85*c0|c1=1.0*c1",
             ]))

  noise.call(:poly, "white", poly_hits.map { |s| ((s / 16) * bar) + ((s % 16) * step) }, 0.03, 95, 0.2,
             drum_chain.call([
               "bandpass=f=6200:w=3000",
               "afreqshift=shift=210",
               "acrusher=bits=8:samples=2:mix=0.35",
               "pan=stereo|c0=0.55*c0|c1=1.0*c1",
               "aecho=0.6:0.4:91|187:0.24|0.12",
               "adecorrelate=stages=3",
             ]))

  noise.call(:open, "white", gather.call(open_per_bar, :hat), 0.45, 9, 0.26,
             drum_chain.call([
               "bandpass=f=7200:w=5200",
               "aphaser=speed=0.5:decay=0.6:delay=3",
               "adecorrelate=stages=4",
               "aecho=0.7:0.55:230|470:0.32|0.18",
               "stereowiden=delay=15:feedback=0.4:crossfeed=0.3:drymix=0.7",
             ]))

  noise.call(:ride, "white", gather.call(ride_per_bar, :hat), 1.6, 2.4, 0.13,
             drum_chain.call([
               "bandpass=f=5400:w=2600",
               "aexciter=level_in=1:level_out=1:amount=2:blend=2:freq=7500",
               "chorus=0.6:0.9:50|60:0.4|0.32:0.25|0.4:2|2.3",
               "aecho=0.8:0.7:410|790|1290:0.4|0.24|0.12",
               "stereotools=mlev=0.7:slev=1.5",
             ]))

  noise.call(:metal, "white", gather.call(metal_per_bar), 0.9, 5, 0.30,
             drum_chain.call([
               "bandpass=f=3100:w=260",
               "bandpass=f=4700:w=200",
               "afreqshift=shift=-37",
               "acrusher=bits=10:samples=3:mix=0.4",
               "flanger=delay=4:depth=6:regen=60:speed=0.14",
               "aecho=0.8:0.7:170|330|610|1130:0.5|0.32|0.18|0.09",
               "highpass=f=900",
               "stereotools=slev=1.8",
             ]))

  noise.call(:tom, "brown", gather.call(tom_per_bar, :ghost), 0.5, 7, 0.34,
             drum_chain.call([
               "bandpass=f=180:w=140",
               "asoftclip=type=atan:threshold=0.7:oversample=4",
               "asubboost=dry=0.9:wet=0.35:decay=0.5:feedback=0.4:cutoff=120",
               "aphaser=speed=0.2:decay=0.5:delay=3.4",
               "aecho=0.7:0.5:130|260|520:0.3|0.16|0.08",
               "stereotools=slev=1.2",
             ]))

  # BLEEPS AND BLOOPS.
  #
  # The Flying Lotus register: short pitched blips that bend as they sound, sat
  # in a lot of delay, panned hard and never quite where the grid is. On
  # Cosmogramma they are the thing that stops a beat being a beat and makes it
  # sound like a broken transmission.
  #
  # A bleep bends UP and a bloop bends DOWN -- that is the whole difference, and
  # the reason both words exist. The bend is inside the sine's phase argument
  # rather than applied afterwards, so the pitch really moves during the note
  # instead of the note being pitch-shifted as a block.
  #
  # Placed on the odd sixteenths the drums leave alone, so they answer the kit
  # rather than doubling it.
  bleep_steps = [3, 7, 11, 15]
  bloop_steps = [5, 13]
  bleep_freqs = [880.0, 1174.7, 987.8, 1318.5, 1046.5, 784.0, 1396.9, 659.3]

  # bleep and bloop are pitched too -- chirps on a per-bar note from
  # bleep_freqs, which is a melody whatever it is called. HATE_MELODY=0 has to
  # take all three or the line is still there: dropping only :acid left these
  # playing and the operator still heard a top line.
  if ENV.fetch("HATE_MELODY", "1") != "0"
  tone.call(:bleep,
            HATE_CYCLE_BARS.times.flat_map { |b|
              bleep_steps.each_slice(2).map(&:first).map { |s|
                t0 = at.call(b, s)
                f = bleep_freqs[b]
                dt = "(t-#{t0})"
                # +40% over the note: a rising chirp, not a tone.
                "between(t,#{t0},#{(t0 + 0.09).round(6)})*0.3*exp(-#{dt}*22)*" \
                  "sin(2*PI*(#{f}*#{dt}+#{(f * 0.4).round(1)}*#{dt}*#{dt}))"
              }
            }.join("+"),
            drum_chain.call([
              "acrusher=bits=7:samples=1:mix=0.45",
              "highpass=f=500",
              "aecho=0.7:0.6:#{(step * 1500).round}|#{(step * 3000).round}|#{(step * 4500).round}:0.42|0.26|0.14",
              "aphaser=speed=0.9:decay=0.55:delay=2",
              "pan=stereo|c0=1.0*c0|c1=0.35*c1",
              "stereotools=slev=1.6",
            ]))

  tone.call(:bloop,
            HATE_CYCLE_BARS.times.flat_map { |b|
              bloop_steps.map { |s|
                t0 = at.call(b, s)
                f = (bleep_freqs[b] / 2.0).round(2)
                dt = "(t-#{t0})"
                # Falling: the bend term is negative and the note is longer.
                "between(t,#{t0},#{(t0 + 0.22).round(6)})*0.26*exp(-#{dt}*9)*" \
                  "sin(2*PI*(#{f}*#{dt}-#{(f * 0.55).round(1)}*#{dt}*#{dt}))"
              }
            }.join("+"),
            drum_chain.call([
              "acrusher=bits=8:samples=2:mix=0.3",
              "lowpass=f=3200",
              "afreqshift=shift=-19",
              "aecho=0.7:0.55:#{(step * 2000).round}|#{(step * 5000).round}:0.4|0.2",
              "pan=stereo|c0=0.35*c0|c1=1.0*c1",
              "stereowiden=delay=20:feedback=0.45:crossfeed=0.35:drymix=0.65",
            ]))
  end

  # HYDRAULIC HISS. A slow breath rather than a hit.
  #
  # The afftfilt stage combs the spectrum by BIN rather than sweeping across
  # time: its expressions have no `t`, which the first attempt assumed and which
  # failed the whole layer to configure. Comment kept out of the string
  # continuation below -- a `#` line between two `\` continuations ends the
  # expression and takes the rest of the call with it.
  hiss_chain = [
    "aformat=channel_layouts=stereo",
    "volume='0.055+0.055*sin(2*PI*t/#{(bar * 2).round(3)})':eval=frame",
    "highpass=f=2400,lowpass=f=11000",
    "afftfilt=real='re*(0.45+0.55*sin(b/18))':imag='im*(0.45+0.55*sin(b/18))':win_size=1024",
    "aecho=0.7:0.6:220|450:0.35|0.2",
    "stereowiden=delay=18:feedback=0.5:crossfeed=0.4:drymix=0.6",
  ].join(",")
  parts[:hiss] = File.join(work, "hiss.wav")
  sh! "ffmpeg", "-y", "-v", "error", "-f", "lavfi",
      "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.9:d=#{cycle}:seed=#{noise_seed(42)}",
      "-af", hiss_chain, "-c:a", "pcm_s16le", parts[:hiss]

  # Loop, gate, and open the filter as the set builds.
  loops = (total / cycle).ceil + 1
  inputs = parts.keys.flat_map { |k| ["-stream_loop", loops.to_s, "-i", parts[k]] }
  chains = parts.keys.each_with_index.map do |k, i|
    gate = hate_gate(k, blocks, bar)
    stage = gate == "1" ? "anull" : "volume='#{gate}':eval=frame"
    "[#{i}:a]atrim=0:#{total},asetpts=PTS-STARTPTS,#{stage}[l#{i}]"
  end
  mix = parts.keys.each_index.map { |i| "[l#{i}]" }.join

  # MASTER. A console chain rather than a limiter: dynamic EQ holding the low
  # mid, a slow bus compressor that breathes with the kick, tape saturation,
  # crossfeed so the width survives headphones, then the limiter last.
  master = "highpass=f=26," \
           "adynamicequalizer=dfrequency=220:dqfactor=1.2:tfrequency=220:tqfactor=1.2:threshold=0.08:ratio=3," \
           "acompressor=threshold=-15dB:ratio=7:attack=2:release=60:makeup=3.5," \
           "asoftclip=type=tanh:threshold=0.86:output=0.95:oversample=4," \
           "aexciter=amount=1.2:blend=1:freq=6800," \
           "crossfeed=strength=0.32:range=0.6," \
           "alimiter=limit=0.96:level_out=0.94"

  graph = "#{chains.join(';')};#{mix}amix=inputs=#{parts.length}:duration=longest:normalize=0,#{master}[out]"

  FileUtils.mkdir_p(File.dirname(destination))
  dmesg("hate: #{HATE_BPM.round} BPM, #{parts.length} layers, #{blocks} blocks, #{(total / 60).round(1)} min, " \
        "dilla drag #{(depth * 100).round}%", unit: "techno0", parent: "dilla0")
  sh! "ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", graph,
      "-map", "[out]", "-t", total.to_s, "-c:a", "libmp3lame", "-b:a", "256k", destination
  FileUtils.rm_rf(work)
  normalise_genre_master!(destination, :techno)
  puts "wrote #{destination}"
  destination
end
def render_techno(destination = File.join(OUTPUT_DIR, "techno_hate.mp3"))
  require_tools! "ffmpeg"
  n_bars = [bars, TECHNO_BARS].max
  beat  = 60.0 / TECHNO_BPM
  bar   = beat * 4
  step  = beat / 4
  total = (bar * n_bars).round(3)

  kick_per_bar = Array.new(TECHNO_BARS) { [0, 4, 8, 12] }
  kick_per_bar[7] = [0, 4, 8, 12, 14, 15]
  clap_per_bar = Array.new(TECHNO_BARS) { [4, 12] }
  clap_per_bar[3] = [4, 12, 14]; clap_per_bar[7] = [4, 10, 12, 14]
  hat_per_bar  = Array.new(TECHNO_BARS) { [2, 6, 10, 14] }
  hat_per_bar[3] = []; hat_per_bar[5] = [0, 2, 4, 6, 8, 10, 12, 14]
  open_per_bar = Array.new(TECHNO_BARS) { [] }
  open_per_bar[3] = [14]; open_per_bar[7] = [14]
  acid_steps = [0, 3, 6, 8, 11, 14]
  bass_notes = [65.41, 65.41, 87.31, 65.41, 98.00, 98.00, 87.31, 65.41]

  cycle = (bar * TECHNO_BARS).round(6)
  kicks = TECHNO_BARS.times.flat_map { |b| kick_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  claps = TECHNO_BARS.times.flat_map { |b| clap_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  hats  = TECHNO_BARS.times.flat_map { |b| hat_per_bar[b].map  { |s| (b * bar + s * step).round(6) } }
  opens = TECHNO_BARS.times.flat_map { |b| open_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  acid_hits = TECHNO_BARS.times.flat_map { |b| bass_notes[b].then { |f| acid_steps.map { |s| [(b * bar + s * step).round(6), f] } } }

  kick_sig = kicks.map do |t|
    tm = (t % cycle).round(6)
    dt = "mod(t,#{cycle})-#{tm}"
    "between(mod(t,#{cycle}),#{tm},#{(tm + 0.18).round(6)})*0.95*exp(-#{dt}*8)*sin(2*PI*(110*#{dt}-250*#{dt}*#{dt}))"
  end
  acid_sig = acid_hits.map do |(t, f)|
    tm = (t % cycle).round(6)
    dt = "mod(t,#{cycle})-#{tm}"
    "between(mod(t,#{cycle}),#{tm},#{(tm + 0.14).round(6)})*0.6*exp(-#{dt}*9)*sin(2*PI*#{f}*#{dt})"
  end
  clap_env = claps.flat_map do |t|
    tm = (t % cycle).round(6)
    t1 = (tm + 0.012).round(6); t2 = (tm + 0.024).round(6)
    dt0 = "mod(t,#{cycle})-#{tm}"; dt1 = "mod(t,#{cycle})-#{t1}"; dt2 = "mod(t,#{cycle})-#{t2}"
    ["between(mod(t,#{cycle}),#{tm},#{(tm + 0.04).round(6)})*exp(-#{dt0}*40)",
     "between(mod(t,#{cycle}),#{t1},#{(t1 + 0.04).round(6)})*exp(-#{dt1}*50)",
     "between(mod(t,#{cycle}),#{t2},#{(t2 + 0.05).round(6)})*exp(-#{dt2}*30)"]
  end
  hat_env = hats.map  { |t| tm = (t % cycle).round(6); dt = "mod(t,#{cycle})-#{tm}"; "between(mod(t,#{cycle}),#{tm},#{(tm + 0.04).round(6)})*exp(-#{dt}*70)" }
  opn_env = opens.map { |t| tm = (t % cycle).round(6); dt = "mod(t,#{cycle})-#{tm}"; "between(mod(t,#{cycle}),#{tm},#{(tm + 0.5).round(6)})*exp(-#{dt}*10)" }

  filt = <<~F
    [0:a]aformat=channel_layouts=stereo,equalizer=f=55:t=o:w=0.7:g=4,
         aeval='tanh(val(0)*2.5)/tanh(2.5)|tanh(val(1)*2.5)/tanh(2.5)',
         acompressor=threshold=-10dB:ratio=6:attack=1:release=40:makeup=3[kick];
    [1:a]aformat=channel_layouts=stereo,
         aeval='tanh(val(0)*3.5)/tanh(3.5)|tanh(val(1)*3.5)/tanh(3.5)',
         equalizer=f=300:t=o:w=2:g=3,equalizer=f=1500:t=o:w=2:g=4,
         lowpass=f=4000[acid];
    [2:a]aformat=channel_layouts=stereo,asplit=3[nc][nh][no];
    [nc]volume='#{safe_volume_env(clap_env)}*0.6':eval=frame,bandpass=f=1500:w=2000,
        aecho=0.5:0.4:30|60:0.2|0.1[clap];
    [nh]volume='#{safe_volume_env(hat_env)}*0.4':eval=frame,highpass=f=8000[hat];
    [no]volume='#{safe_volume_env(opn_env)}*0.3':eval=frame,bandpass=f=7000:w=5000[open];
    [kick][acid][clap][hat][open]amix=inputs=5:weights=1.4 1.0 0.7 0.5 0.4:duration=longest[drums];
    [drums]highpass=f=30,acompressor=threshold=-14dB:ratio=8:attack=1:release=50:makeup=4[drums_comp];
    [drums_comp]aeval='tanh(val(0)*1.8)/tanh(1.8)|tanh(val(1)*1.8)/tanh(1.8)'[drums_sat];
    [drums_sat]equalizer=f=80:t=o:w=0.8:g=2,equalizer=f=8000:t=o:w=2:g=2[master_eq];
    [master_eq]alimiter=level_in=1.0:level_out=0.90:limit=0.85:attack=2:release=20[out]
  F

  FileUtils.mkdir_p(File.dirname(destination))
  sh! "ffmpeg", "-y",
      *lavfi("aevalsrc='#{expr_sum(kick_sig)}':d=#{total}:s=#{SAMPLE_RATE}"),
      *lavfi("aevalsrc='#{expr_sum(acid_sig)}':d=#{total}:s=#{SAMPLE_RATE}"),
      *lavfi("anoisesrc=color=white:r=#{SAMPLE_RATE}:amplitude=0.5:d=#{total}:seed=#{noise_seed(19)}"),
      "-filter_complex", filt.tr("\n", " "), "-map", "[out]", "-b:a", "320k", destination
  normalise_genre_master!(destination, :techno)
  puts "wrote #{destination}"
end
