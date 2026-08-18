# frozen_string_literal: true
#
# The render seed: one draw per render, everything else derived from it.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# RENDER_SEED reached patch_cycle_seed above and stopped there. It never crossed
# into ffmpeg, and ffmpeg is where most of this engine's randomness lives:
# anoisesrc takes a `seed` whose default is -1, meaning a fresh random seed per
# process, and all 31 call sites in this file left it at the default.
#
# That noise is not a bed under the drums. It IS the snare, the hat, the shaker,
# the brush, the crackle and the rumble -- CRATE_PERCUSSION synthesises a shaker
# as "a burst of high noise and nothing else". So every render drew new
# percussion.
#
# Measured, two renders of one track with RENDER_SEED pinned: identical length,
# 99.0% of sample frames different, the difference sitting 2.3 dB below the
# signal itself. "Set it and renders are reproducible and comparable" was true
# of patch selection and of nothing else, which is the more dangerous kind of
# wrong -- the note above says several past comparisons were probably reading
# patch variance rather than the change under test, and this says they were also
# reading a different set of drums.
#
# Returns -1 when RENDER_SEED is unset: that is ffmpeg's own default and exactly
# the per-process variation this file already documents as the unpinned
# behaviour. Pinning stays opt-in; it just now pins the whole render.
#
# `tag` separates the sites, and it has to. One seed shared across all of them
# makes the snare's noise and the hat's noise the same signal -- correlated in a
# way two noise sources never are, and audible as phasing rather than as two
# drums. Knuth's multiplicative constant, folded to anoisesrc's 0..UINT32_MAX.
NOISE_SEED_STRIDE = 2_654_435_761
NOISE_SEED_MODULUS = 4_294_967_296

def render_pinned? = !ENV["RENDER_SEED"].to_s.empty?

# Ruby randomises String#hash and Symbol#hash per process -- SipHash with a key
# drawn at startup, so hash-flooding cannot be aimed at a long-running server.
# Measured, three processes asked for "db_major_minor_fall".hash return
# 1631596481632401333, -1643377148673927661 and -1069425221180396255.
#
# Twenty-six sites in this file built seeds out of that -- the track name, the
# drum role, the groove feel, the chord symbol, the section -- each one reading
# as deterministic, since the same track name gives the same seed, and none of
# them deterministic across two runs. RENDER_SEED was being added to a random number,
# which is why pinning it changed nothing: the pin was real and everything it
# was added to was not.
#
# djb2, which is stable because it is written here rather than provided by the
# runtime. Non-negative by construction, so the .abs these sites carried is no
# longer needed.
def stable_hash(obj)
  obj.to_s.each_byte.reduce(5381) { |a, b| ((a * 33) + b) % NOISE_SEED_MODULUS }
end

# A stable number from a tag and the pinned seed. String tags are hashed rather
# than counted, because a positional counter changes the moment anything is
# reordered and a render that changes when the code is rearranged is not pinned
# in any useful sense.
def seed_for(tag)
  h = tag.is_a?(Integer) ? tag : tag.to_s.each_byte.reduce(7) { |a, b| ((a * 31) + b) % NOISE_SEED_MODULUS }
  (ENV["RENDER_SEED"].to_i + (h * NOISE_SEED_STRIDE)) % NOISE_SEED_MODULUS
end

def noise_seed(tag) = render_pinned? ? seed_for(tag) : -1

# The unpinned branch of both of these is the existing behaviour verbatim, so
# nothing changes for anyone who has not set RENDER_SEED.
def render_rand(tag)
  return rand unless render_pinned?

  seed_for(tag).fdiv(NOISE_SEED_MODULUS)
end

# Array#sample under a pin, keyed by tag rather than by call order. Order-keying
# matters here: drum_sample_path is called once per role and a shared sequential
# RNG would hand a role a different file depending on which roles were resolved
# before it, so the same seed would give different kits in different arrangements.
def render_pick(list, tag)
  list = Array(list)
  return nil if list.empty?
  return list.sample unless render_pinned?

  list[seed_for(tag) % list.length]
end

# Random.new(Time.now.to_i + Process.pid), which four stream-evolution sites
# used, cannot be pinned by anything -- it re-seeds from the clock on every run
# by construction.
def render_rng(tag, drift: 0)
  return Random.new(seed_for(tag)) if render_pinned?

  Random.new(Time.now.to_i + Process.pid + drift)
end
