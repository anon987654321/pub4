# frozen_string_literal: true
#
# The Dilla drum part: patterns, fills, ghosts, sections.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def drum_feel_key(feel)
  feel = feel.to_sym
  return feel if DRUM_PATTERN_SETS.key?(feel)
  :default
end

# Morphing the kit across a track: Detroit, then the LA beat scene, then
# industrial techno.
#
# A track has exactly one feel. Patterns rotate inside it bar to bar, but the
# vocabulary never changes, so a long piece states one idea for its whole
# length. The operator asked for the drums to travel between the three
# families "smoothly", which is a thing this had no way to express.
#
# The voices hand over one at a time, and that is the whole trick. Switching
# every voice on the same bar is a cut -- the listener hears a new song. A
# producer moves the hats first, because the hats are the least load-bearing
# part of the bar and the ear forgives them changing; then the snare, which is
# the reference the bar is counted against; and the kick last, because the kick
# is what makes it the same piece of music. By the time the kick moves, the
# rest of the kit has already been in the new idiom for a while and the change
# lands as arrival rather than as edit.
#
# DRUM_MORPH=0 turns it off and every voice takes the track's own feel, which
# is the previous behaviour exactly.
DRUM_MORPH_PATH = %i[detroit_stumble la_beat_scene techno_house].freeze

# Fractions of the track at which each voice has completed its move. Hats are
# a third of the way ahead of the kick throughout.
# A bigger lead means this voice is further along the path, so it changes
# EARLIER. The hats therefore carry the largest number and the kick zero --
# written the other way round first, which put the kick in the new idiom four
# bars in while the hats were still in the old one. That is the handover
# backwards: the load-bearing voice moved first and the change read as a cut.
DRUM_MORPH_LEAD = { hats: 0.30, opens: 0.30, ghosts: 0.20, snares: 0.12, kicks: 0.0 }.freeze

def drum_morph_enabled?
  ENV.fetch("DRUM_MORPH", "0") != "0"
end

def drum_morph_feel(bar, role)
  return nil unless drum_morph_enabled?

  n_bars = @render_total_bars.to_i
  return nil unless n_bars.positive?

  path = DRUM_MORPH_PATH
  # Where this voice is in its own journey: its lead pulls it forward, so at
  # any moment the hats are further along the path than the kick.
  lead = DRUM_MORPH_LEAD.fetch(role.to_sym, 0.15)
  t = ((bar.to_f / n_bars) + lead).clamp(0.0, 0.999)
  path[(t * path.length).floor.clamp(0, path.length - 1)]
end

def drum_pattern_seed(feel)
  (stable_hash(feel) + (@render_seed || 0)) % 10_000
end

def drum_pattern_pick(bar, feel, role)
  if (learned = learned_drum_steps(role))&.any?
    return learned.dup
  end
  # A morph overrides the track's feel for THIS voice only, which is what makes
  # the handover staggered rather than simultaneous.
  feel = drum_morph_feel(bar, role) || feel
  sets = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel))
  # fetch(role) raised KeyError when a feel has no entry for this voice, and the
  # morph made that reachable: callers guard on the TRACK's feel
  # (`if sets[:perc]` in dilla_ghost_steps) while this method had already swapped
  # in the morphed one, so the guard checked a different hash from the fetch.
  # 94 KeyErrors across ~47 tracks in one run. A missing voice is a legitimate
  # thing for a feel to say -- it means "this idiom has no percussion" -- so it
  # returns nothing instead of raising.
  pool = sets[role]
  return [] if pool.nil? || pool.empty?
  seed = drum_pattern_seed(feel)
  phrase = bar % 4
  idx = (phrase + seed + (bar / 8)) % pool.length
  steps = Array(pool[idx]).dup
  # Fill bar: extra kick cluster on the & of 4 (step 15) for Dilla-style turns.
  if role == :kicks && bar.positive? && (bar % 8) == 7
    steps << 15 unless steps.include?(15)
  end
  steps.uniq.sort
end

def dilla_kick_pattern(bar, _n_bars, feel)
  drum_pattern_pick(bar, feel, :kicks)
end

def dilla_snare_steps(bar, feel, section:)
  return [] if section == :breakdown
  steps = if DillaGroove.kick_snare_swap?
            drum_pattern_pick(bar, feel, :kicks)
          else
            drum_pattern_pick(bar, feel, :snares)
          end
  pool = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel), DRUM_PATTERN_SETS[:default])[:snares]&.flatten || steps
  steps = DillaGroove.markov_steps(bar, :snare, steps + pool) if steps.any?
  if halftime?
    steps = steps.map { |s| s == 4 ? 8 : s }.reject { |s| s == 12 && bar.even? }
    steps = [8] if steps.empty?
  end
  steps -= [10, 14] if section == :intro
  steps.uniq.sort
end

def dilla_fill_bar?(bar, section)
  return false if %i[intro breakdown].include?(section)
  tier = ghost_tier_for(bar, section)
  fill_mul = GHOST_TIERS.fetch(tier, GHOST_TIERS[:pocket])[:fill_mul]
  return false if tier == :whisper && bar % 16 != 15
  on_phrase = bar % 8 == 7 || (bar.positive? && bar % 16 == 15)
  return false unless on_phrase
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    prof = @composition_session.profile_at(bar)
    rate = prof[:fill_rate].to_f * fill_mul
    return Random.new(bar * 31 + @composition_session.generation).rand < rate.clamp(0.05, 0.95)
  end
  tier == :accent || bar % 8 == 7 || (bar.positive? && bar % 16 == 15)
end

def schedule_drum_fills!(events, bar, base, step_p, swing, quintuplet, timing, beat_p, sec_gain, feel, section)
  return unless dilla_fill_bar?(bar, section)
  seed = drum_pattern_seed(feel) + bar
  bpm = (60.0 / beat_p)
  DRUM_FILL_SETS[:snare][(bar / 8 + seed) % DRUM_FILL_SETS[:snare].length].each do |step|
    t = [base + step * step_p +
         dilla_swing_offset(step, step_p, swing, quintuplet:, bar:, bpm:) +
         dilla_timing_ms(:snare, bar, step, timing, beat_p) / 1000.0, 0.0].max
    t = DillaGroove.apply_event_timing!(t, role: :snare, beat_p:, bar:, step:,
                                        bpm:, section:)
    vel = step >= 10 ? 0.54 : 0.46
    events[:snare] << [t.round(6), dilla_velocity(vel, bar, step, spread: 0.06) * sec_gain]
  end
  if kicks_enabled?
    DRUM_FILL_SETS[:kicks][(bar / 8 + seed) % DRUM_FILL_SETS[:kicks].length].each do |step|
      t = [base + step * step_p +
           dilla_swing_offset(step, step_p, swing, quintuplet:, bar:, bpm:) +
           dilla_timing_ms(:kick_sync, bar, step, timing, beat_p) / 1000.0, 0.0].max
      t = DillaGroove.apply_event_timing!(t, role: :kick, beat_p:, bar:, step:,
                                          bpm:, section:)
      events[:kick] << [t.round(6), dilla_velocity(0.4, bar, step, spread: 0.05) * sec_gain * kick_velocity_scale]
    end
  end
  tier = ghost_tier_for(bar, section)
  DRUM_FILL_SETS[:ghosts][(bar / 8 + seed) % DRUM_FILL_SETS[:ghosts].length].each do |step|
    t = [base + step * step_p +
         dilla_swing_offset(step, step_p, swing, quintuplet:, bar:, bpm:) +
         dilla_timing_ms(:ghost, bar, step, timing, beat_p) / 1000.0, 0.0].max
    t = DillaGroove.apply_event_timing!(t, role: :ghost, beat_p:, bar:, step:,
                                        bpm:, section:)
    vel = apply_ghost_tier_vel(dilla_velocity(0.32, bar, step, spread: 0.07) * sec_gain, tier)
    events[:ghost] << [t.round(6), vel]
  end
end

def schedule_hat_roll!(events, bar, base, step_p, swing, quintuplet, timing, beat_p, sec_gain, section)
  return unless bar % 8 == 7 && !%i[intro breakdown].include?(section)
  bpm = (60.0 / beat_p)
  # 32nd-note roll on the last beat of every 8-bar phrase (steps 12–15.75).
  16.times do |sub|
    step = 12.0 + sub * 0.25
    t = [base + step * step_p +
         dilla_swing_offset(step.floor, step_p, swing, quintuplet:, bar:, bpm:) +
         dilla_timing_ms(:hat_up, bar, step.floor, timing, beat_p) / 1000.0, 0.0].max
    t = DillaGroove.apply_event_timing!(t, role: :hat_up, beat_p:, bar:, step: step.floor,
                                        bpm:, section:)
    accel = 0.34 + (sub / 15.0) * 0.22
    events[:hat] << [t.round(6), dilla_velocity(accel, bar, step.floor, spread: 0.1) * sec_gain]
  end
end

def dilla_ghost_steps(bar, feel, section: :main)
  steps = drum_pattern_pick(bar, feel, :ghosts)
  sets = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel))
  steps += drum_pattern_pick(bar, feel, :perc) if sets[:perc]
  pool = sets[:ghosts]&.flatten || steps
  steps = DillaGroove.markov_steps(bar, :ghost, steps + pool) if steps.any? && ENV["MARKOV_DRUMS"] != "0"
  tier = ghost_tier_for(bar, section)
  scale = GHOST_TIERS.fetch(tier, GHOST_TIERS[:pocket])[:steps_scale]
  if scale < 1.0
    steps = steps.select.with_index { |_, i| i.even? || bar.odd? }
  elsif scale > 1.0
    extras = [2, 6, 14].select { |s| !steps.include?(s) && Random.new(bar * 71 + stable_hash(feel)).rand < 0.38 }
    steps += extras
  end
  steps.uniq.sort
end

def dilla_open_steps(bar, feel, section:)
  return [] if section == :breakdown
  opens = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel))[:opens]
  return [] unless opens
  return opens if feel == :loose_pocket && bar % 8 == 5
  return [opens[(bar / 2) % opens.length]] if [1, 3].include?(bar % 4)
  []
end

def dilla_section_bounds(n_bars)
  intro = [[(n_bars * 0.12).round, 4].max, (n_bars * 0.22).round].min
  outro = [[(n_bars * 0.10).round, 4].max, (n_bars * 0.18).round].min
  body = [n_bars - intro - outro, 8].max
  # A phrase length, never longer than the body. Both halves of that matter, and
  # each was learned from a render that sounded broken.
  #
  # Never longer than the body: with the old floor of 16, a 16-bar render had a
  # 9-bar body against a 16-bar cycle, so `pos` never exceeded 8 while breakdown
  # began at 12 and build at 14 -- both unreachable. Every render up to about 21
  # bars was intro, main, outro and nothing else, which is exactly what "loops
  # over and over with no variation" sounds like. The arrangement was never
  # missing; it was unreachable at the lengths anyone actually renders.
  #
  # But a phrase length, not the whole body: letting the cycle equal the body
  # meant a 32-bar render had a 24-bar cycle -- eighteen consecutive bars of
  # :main with a single breakdown near the end. The loudness envelope measured
  # 3.1 dB of range against 8.6 dB on demo29, one of the two tracks kept on
  # merit, whose envelope dips every four or five bars. Flat arrangement, not
  # flat compression: the same render measures LRA 1.8 with loudnorm disabled.
  #
  # SECTION_CYCLE overrides it; 16 is two breakdowns across 32 bars, 8 is four.
  #
  # Floor of 5, not 4. At 4 the two thresholds collide -- brk = (4*0.75).floor = 3
  # and bld = (4*0.875).floor = 3 -- so `pos >= brk && pos < bld` is never true and
  # :breakdown becomes unreachable, every one of those bars landing on :build
  # instead. That is the opposite of what a shorter cycle is asked for. 5 is the
  # shortest cycle that can express both (brk 3, bld 4), and an unparseable value
  # reaches the floor the same way, since "".to_i is 0.
  cycle = [(ENV["SECTION_CYCLE"] || 8).to_i, body].min.clamp(5, 32)
  { intro:, outro:, cycle:, body_start: intro }
end

def dilla_section_legacy(bar, n_bars)
  b = dilla_section_bounds(n_bars)
  return :outro if bar >= n_bars - b[:outro]
  return :intro if bar < b[:intro]
  pos = (bar - b[:body_start]) % b[:cycle]
  brk = (b[:cycle] * 0.75).floor
  bld = (b[:cycle] * 0.875).floor
  return :breakdown if pos >= brk && pos < bld
  return :build if pos >= bld
  :main
end

# --- Parts entering and leaving --------------------------------------------
#
# The engine has known about sections for a long time -- intro, main, breakdown,
# build, outro, with twenty-six places in this file that branch on which one is
# playing. What none of them did was change WHICH INSTRUMENTS are sounding. Every
# layer started at bar one, played to the end, and stopped. Bar 1 and bar 16 had
# the same parts at the same density, which is what "it loops over and over" and
# "most were repetitive trash" describe: not a lack of ideas, a lack of anything
# arriving or leaving.
#
# An arrangement is mostly subtraction. The intro states the chords with almost
# nothing under them; the drums arrive and that arrival is the event; the
# breakdown takes them away again so their return means something; the outro
# removes one thing at a time. None of that needs new material -- it is the
# material already rendered, gated in time.
#
# Gains rather than mutes, mostly. A layer dropping to zero and back is a hard
# edit and sounds like one; dropping to a third leaves the part audible as a
# memory of itself. Zero is reserved for the places a hard entrance is the point.
#
# :harm is here with no reductions on purpose. render_dilla asks for a :harm
# envelope on the analog pad and always has, and because the table never
# mentioned :harm that call has been a silent no-op for its whole life --
# section_layer_windows returns an empty list for an unknown layer and
# apply_section_envelope returns the chain untouched. Declaring it empty makes
# the two lists agree without changing a single sample: the pad stays at full
# level in every section, exactly as it does today. What it buys is that
# SECTION_LAYERS_DECLARED and SECTION_LAYERS_APPLIED can now be compared, so the
# next layer wired to nothing fails a test instead of looking like a feature.
#
# Giving the pads an actual section shape is a musical decision and belongs to
# the operator, not to the commit that noticed the wiring was dead.
SECTION_LAYER_GAIN = {
  intro:     { drums: 0.0,  bass: 0.30, lead: 0.0,  chops: 0.0,  sample: 0.55, harm: 1.0 },
  main:      { harm: 1.0 },
  breakdown: { drums: 0.0,  bass: 0.55, chops: 0.0, harm: 1.0 },
  build:     { lead: 0.0,   sample: 0.7, harm: 1.0 },
  turn:      { lead: 0.0,   harm: 1.0 },
  outro:     { drums: 0.45, bass: 0.5,  lead: 0.0,  chops: 0.0, harm: 1.0 },
}.freeze

# The arrangement the table above declines to make, offered rather than imposed.
#
# The note above is right that giving the pads a section shape is the operator's
# decision, and it stays the operator's: nothing here is reached unless
# SECTION_LAYERS=full, and the default table is untouched. What was missing is
# that the decision could not be TAKEN -- there was no shape to switch on, so
# "belongs to the operator" meant "belongs to nobody".
#
# Why it is worth having something to switch on. Measured on a default 32-bar
# render: full-band RMS across eight four-bar sections came out -19.9, -20.7,
# -21.0, -20.9, -20.9, -21.3, -20.8, -20.6. A 1.4 dB spread over the whole track,
# and flat inside 0.7 dB after bar 8. The drums, bass and sample DO follow the
# table -- their envelopes are in the graph and they work; the exact clause was
# tested in isolation and mutes by 80 dB. But that render's six channels were
# drums, harm, bass, analogpad, vinyl and rumble at weights 0.95, 1.12, 1.15,
# 0.62, 0.35 and 0.25, and four of the six -- carrying more than half the
# weight, including the loudest single channel -- had no section shape at all.
# An arrangement that moves the quiet half of a mix is not audible as one.
#
# The numbers below are gains, and the first version of this table used them as
# gains: pads at 0.72 through the intro, 1.12 in a breakdown, texture up to 1.85.
# It measured as nothing, and the reason turned out to be worth more than the
# table.
#
# An arrangement is a change in WHAT IS PLAYING, not in how loud it is. Measured
# on a 5.8-minute render, altering it at a known second and asking a spectral
# boundary detector what it can see:
#
#   a timbre change (lowpass to 800 Hz)   novelty peak 0.0044 -> 0.0624, found
#                                         at 173.9 s against an actual 174.0
#   a 6 dB level drop at the same second  0.0044 -> 0.0066, and nine spurious
#                                         boundaries rather than one real one
#
# Fourteen times against one and a half. And the two records this engine is
# measured against reach peaks of 0.0131 and 0.0252 with two to four boundaries
# each, while dilla reached 0.0044 with none -- at 32 bars and, unchanged, at
# 128. Four times the material and the same structure, because every lever the
# engine had (this table, FORM, FORM_FIT, the grain settings) moves a level.
#
# So the layers that carry an arrangement LEAVE. A gain of 0.0 is a part not
# playing, which is the one thing in this table that produces a boundary, and it
# is now what the intro and the breakdown do to the harmonic bus -- the loudest
# channel in the mix and, until this, the one that never stopped.
#
# Texture is the exception and stays a gain: vinyl noise and turntable rumble
# come UP when the band drops out, because a record's surface is what is audible
# when nothing else is, and that is the difference between a breakdown and a
# hole. It is not carrying the boundary; the parts that stop are.
SECTION_LAYER_GAIN_ARRANGED = {
# harm ducks here rather than stopping, and that is a deliberate half-measure.
#
# The measurements above argue for stopping: a timbre change reads 14x against
# a level change's 1.5x. What is missing is evidence that a removal here
# SOUNDS better, as opposed to measuring better -- and the harmony bus is the
# loudest channel in the mix, so taking it out for a whole section is a large
# musical decision to make on a detector's behalf.
#
# The mechanism is not in doubt. Section envelopes were verified end to end,
# against a reference render with the kit turned off entirely: over a 16.4 s
# intro where the table mutes the drums, kick-band RMS reads -29.0 dB against
# -29.6 for a take with no kit at all and -25.4 for one with the envelope
# disabled. It lands on the no-kit reference. In a control window where the
# same take plays its kit, it reads -25.6 against -25.8. The envelope does
# exactly what it says.
#
# What that reference also shows is why this is easy to get wrong: the kit's
# ENTIRE contribution to that band is 4.2 dB, because it is 21% of the mix
# weight sitting under a bass at 1.15. A perfect mute looks like 3.6 dB here,
# not 40, and without a no-kit arm to compare against it reads as a failure.
# Two days of hypotheses were built on exactly that misreading.
#
# So: the removal is available (set 0.0) and is not the default. See the note
# on FORM_FIT for the other half -- a section only reads as one if it also
# lasts longer than a bar.
  # harm STOPS in the intro and the breakdown, and the duration rule below is
  # what makes that safe.
  #
  # The measurements say a section boundary needs a change in what is PLAYING,
  # not in how loud it is: on a real render a timbre change at a known second
  # moved the novelty detector 14x and a 6 dB level change 1.5x. So the loudest
  # channel in the mix leaves, rather than ducking.
  #
  # The reason this was a duck until now was a misreading, and it is worth
  # keeping. A 128-bar take with the harmony muted for 43 seconds measured
  # 1.6 dB LOUDER across 250-2000 Hz than one without the envelope, which read as
  # "the envelope does nothing". It was not: the arms were not matched -- one
  # cycled its form and the other did not -- and a later three-arm test with a
  # no-kit reference showed the envelopes land exactly on the reference. The
  # mechanism was never broken; the comparison was.
  #
  # What the same reference showed is why this is easy to get wrong: a channel's
  # entire contribution to a band can be 4 dB, so a perfect mute looks like 3.6
  # and reads as a failure unless something with the channel genuinely absent is
  # measured beside it.
  intro:     { drums: 0.0,  bass: 0.30, lead: 0.0,  chops: 0.0,  sample: 0.55,
               harm: 0.0,  pad: 0.85, texture: 1.60 },
  main:      { harm: 1.0,  pad: 1.0,  texture: 1.0 },
  breakdown: { drums: 0.0,  bass: 0.55, chops: 0.0,
               harm: 0.0,  pad: 1.20, texture: 1.85 },
  build:     { lead: 0.0,   sample: 0.7,
               harm: 1.06, pad: 0.90, texture: 1.25 },
  turn:      { lead: 0.0,   harm: 1.0, pad: 1.08, texture: 1.15 },
  outro:     { drums: 0.45, bass: 0.5,  lead: 0.0,  chops: 0.0,
               harm: 0.85, pad: 1.10, texture: 1.70 },
}.freeze

def section_layers_enabled? = ENV.fetch("SECTION_LAYERS", "1") != "0"

# Which table is in force. Two tables rather than one with a flag inside it,
# because the default one is what every existing render was made with and the
# cheapest way to keep that true is to leave it alone.
def section_layer_table = section_layers_full? ? SECTION_LAYER_GAIN_ARRANGED : SECTION_LAYER_GAIN

# Every layer either table has an opinion about. Both, because the pairing below
# is what catches a layer wired to nothing, and a layer declared only under
# SECTION_LAYERS=full is exactly as capable of being wired to nothing.
SECTION_LAYERS_DECLARED = (SECTION_LAYER_GAIN.values.flat_map(&:keys) +
                           SECTION_LAYER_GAIN_ARRANGED.values.flat_map(&:keys)).uniq.freeze

# Layers whose envelope is actually asked for somewhere. Two of the five were
# not, and that is what this pair of constants exists to stop happening again.
#
# :lead and :chops carried gains in the table above -- lead silent through the
# intro, the breakdown, the build and the outro; chops silent through three of
# them -- and nothing ever called apply_section_envelope for either. The most
# dramatic instruction in the arrangement, on the layer a listener notices
# first, was a hash entry nobody read. Meanwhile :harm WAS applied, to the
# analog pad, and the table says nothing about :harm, so section_layer_windows
# returned an empty list and that call has always been a no-op too.
#
# Neither failed. Both are the shape of defect this repository keeps finding:
# a declaration with no reader, indistinguishable from a working feature until
# somebody diffs the two lists. So they get diffed, in a test.
SECTION_LAYERS_APPLIED = %i[drums bass sample lead chops harm pad texture].freeze

# The time windows, in seconds, where this layer is not at full level.
#
# Contiguous bars sharing a gain are merged into one window: a 16-bar track
# yields three or four windows rather than sixteen, and ffmpeg is being handed a
# filter string, not a score.
def section_layer_windows(layer, n_bars, bar_p)
  return [] unless section_layers_enabled? && n_bars.to_i.positive?

  spans = []
  (0...n_bars).each do |bar|
    gain = section_layer_table.dig(dilla_section(bar, n_bars), layer)
    next if gain.nil?

    if spans.last && spans.last[:gain] == gain && spans.last[:to] == bar
      spans.last[:to] = bar + 1
    else
      spans << { from: bar, to: bar + 1, gain: }
    end
  end
  spans.map { |s| [(s[:from] * bar_p).round(3), (s[:to] * bar_p).round(3), s[:gain]] }
       .map { |from, to, gain| [from, to, survivable_gain(gain, to - from)] }
end

# A removal too short to read as a section becomes a duck instead.
#
# Both halves of this come from the same measurement. A boundary needs a change
# in WHAT IS PLAYING -- 14x against a level change's 1.5x -- and it needs to last
# long enough to be heard as a section rather than as a fault. The novelty
# detector's kernel is twelve seconds either side, and a listener is not much
# more generous.
#
# The legacy form's breakdowns are ONE BAR: 2.7 seconds at 88 BPM, three times in
# thirty-two. Taking the loudest channel in the mix out for 2.7 seconds is a beat
# drop, which is a real gesture -- but three of them in ninety seconds is a
# stutter, and it is not what the table means by "breakdown". So a full removal
# survives only in a section long enough to be one, and anywhere shorter it
# becomes a duck that still moves the balance without punching a hole.
#
# Eight seconds is roughly three bars at these tempos: long enough that the ear
# settles into the new instrumentation, short enough that a four-bar breakdown
# still qualifies. Nothing else in the table is affected -- this only ever
# softens a 0.0, and never touches a gain that was already a level change.
SECTION_REMOVAL_MIN_SEC = 8.0
SECTION_SHORT_REMOVAL_DUCK = 0.45

def survivable_gain(gain, seconds)
  return gain unless gain.to_f.zero?
  return gain if seconds >= SECTION_REMOVAL_MIN_SEC

  SECTION_SHORT_REMOVAL_DUCK
end

# volume with `enable` rather than one expression: each window is its own stage,
# which reads as what it is and lets ffmpeg do the timeline arithmetic. An empty
# result is an empty string, so a layer with nothing to say costs nothing.
#
# A short fade at each edge, because a gain change on a sustained pad is a click
# otherwise. 40ms is under a thirty-second note at any tempo here and inaudible
# as a fade, which is the point -- it should sound like the part left, not like
# somebody turned it down.
SECTION_EDGE_FADE = 0.04

def section_layer_filter(layer, n_bars, bar_p)
  windows = section_layer_windows(layer, n_bars, bar_p)
  return "" if windows.empty?

  windows.map do |from, to, gain|
    a = (from + SECTION_EDGE_FADE).round(3)
    b = (to - SECTION_EDGE_FADE).round(3)
    next "" if b <= a

    "volume=#{gain}:enable='between(t,#{a},#{b})'"
  end.reject(&:empty?).join(",")
end

# Prefix a layer's own chain with its section envelope.
#
# The envelope goes immediately after the input label -- "[0:a]" and friends --
# because a filtergraph stage is "[in]filters[out]" and the volume has to be
# inside that, not in front of the label. Inserted at the front of the whole
# string it produces "volume=...,[0:a]..." which ffmpeg rejects outright.
#
# Returns the chain untouched when the layer has no windows, so a track whose
# sections all want everything at full level pays nothing for this.
def apply_section_envelope(chain, layer, n_bars, bar_p)
  env = section_layer_filter(layer, n_bars, bar_p)
  return chain if env.empty? || chain.to_s.empty?

  chain.sub(/\A(\[[^\]]+\])/) { "#{Regexp.last_match(1)}#{env}," }
end

# The same envelope, for a layer that has no bus to hang it on.
#
# The lead is synthesised into the harmonic render rather than mixed as its own
# stream, so there is no filtergraph label to prefix and its section gain has to
# be applied to the notes. Events are [time, velocity, chord, sustain]; a gain
# of zero drops the note rather than playing it at zero, because a MIDI note-on
# at velocity 0 is a note-off in some synths and a quiet note in others.
#
# Off by default under SECTION_LAYERS=1, which is what every existing render was
# made with. SECTION_LAYERS=full turns on the layers the table has always
# declared. Wiring them silently would change the sound of every take with a
# lead in it, and that is not a checker's call to make -- see
# WIRING_DEAD_METHOD_BASELINE's note, which says the same thing about the two
# sound stages nobody connected.
def section_layers_full? = ENV["SECTION_LAYERS"].to_s.downcase == "full"

def apply_section_envelope_to_events(events, layer, n_bars, bar_p)
  return events unless section_layers_full? && events.is_a?(Array) && events.any?

  windows = section_layer_windows(layer, n_bars, bar_p)
  return events if windows.empty?

  kept = events.filter_map do |event|
    at = event[0].to_f
    _from, _to, gain = windows.find { |from, to, _| at >= from && at < to }
    next event if gain.nil?
    next nil if gain.zero?

    scaled = event.dup
    scaled[1] = (event[1].to_f * gain).round(4)
    scaled
  end
  dropped = events.length - kept.length
  if dropped.positive?
    dmesg("section: #{layer} drops #{dropped} of #{events.length} note(s) outside its sections",
          unit: "harm0", parent: "dilla0")
  end
  kept
end

def dilla_section(bar, n_bars)
  fs = form_section_at(bar, n_bars)
  return fs if fs
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    return COMPOSITION_SECTION_KIND.fetch(@composition_session.section_at(bar), :main)
  end
  dilla_section_legacy(bar, n_bars)
end

def dilla_section_gain(bar, n_bars, chord_phases: nil, pad_chords: nil, chord_bars: 2, phrase_bars: nil)
  sec_gain = if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
               prof = @composition_session.profile_at(bar)
               tension = @composition_session.tension_at(bar)
               (prof[:drums] * 0.35 + prof[:harmony] * 0.35 + tension * 0.3).clamp(0.28, 1.0)
             else
               case dilla_section_legacy(bar, n_bars)
               when :intro then 0.72
               when :breakdown then 0.58
               when :build then 0.88
               when :outro then 0.62
               else 1.0
               end
             end
  phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars:, phrase_bars:)
  sec_gain * (phase ? phase_gain_multiplier(phase) : 1.0)
end
