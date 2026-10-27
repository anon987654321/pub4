# frozen_string_literal: true

# Random Effects
# A random chain, grown rather than sampled.
#
# A random subset without a shared process is the Photoshop filter menu, and it
# looks like one: tilt-shift and selenium toning and teal-orange on the same
# frame, each at half strength, none of them agreeing about what the picture is.
# What makes a chain read as a grade instead is that its steps belong to one
# process — a stock, a development, a print, one way of having been damaged.
#
# Nobody declares those families here. They are read off the eighty-two presets,
# each a colourist's answer to the same question: a candidate may
# join the chain only where some preset already puts it beside everything
# already picked. The graph is dense enough to carry it — greedy walks run five
# to thirteen effects, median eight — so the constraint buys coherence without
# costing variety.
RANDOM_CHAIN_LENGTH = (4..8)
# Grain is not optional, ever. The argument of this whole file is that an
# emulsion is a physical process, and a chain with no crystals in it is a colour
# filter with opinions.
RANDOM_ALWAYS = "grain"
RANDOM_VARIATIONS = (5..10)
RANDOM_VARIATION_RANGE = RANDOM_VARIATIONS.freeze

RANDOM_ANALOG_CORE = %w[
  film_curve halation stock_matrix dir_coupler adjacency_effects film_base_density
  orange_mask print_film paper_texture dilla_head_bump dilla_tape_saturation
  dilla_vinyl_bandlimit dilla_phasy dilla_console_sum
].freeze

# Grain is removed from every lane pool: `random_finish` appends the
# always-grain once at the end, and a lane draw putting another grain earlier
# in the chain made "grainx2" — two passes of what compositors forbid stacking
# ("don't mix grain on top of grain in the plate"). One grain pass, last.

RANDOM_LANES = {
  subtle_analog: {
    effects: %w[
      spectral_temp film_curve stock_matrix dir_coupler adjacency_effects halation
      film_base_density orange_mask print_film shadow_lift highlight_roll micro_contrast
      warmth
    ].freeze,
    strength: (0.16..0.42)
  },
  cinematic_color: {
    effects: %w[
      spectral_temp color_temp film_curve stock_matrix halation orange_mask print_film
      tonemap split_toning teal_orange warmth shadow_lift highlight_roll micro_contrast
    ].freeze,
    strength: (0.24..0.58)
  },
  artistic_analog: {
    effects: %w[
      film_curve halation stock_matrix dir_coupler adjacency_effects bloom_pro
      double_exposure lith_print cyanotype technicolor faded_print polaroid_frame
      soft_focus golden_hour_glow cross_process lens_flare film_scratches
      dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit dilla_phasy
    ].freeze,
    strength: (0.34..0.72)
  },
  bleeding_edge_analog: {
    effects: %w[
      film_curve halation stock_matrix dilla_head_bump dilla_tape_saturation
      dilla_vinyl_bandlimit dilla_phasy dilla_console_sum vhs_luma_bleed
      vhs_chroma_delay vhs_head_switch_band vhs_tracking_noise vhs_interlace_comb
      crt_phosphor_bloom crt_scanlines minidv_block_dropout hi8_chroma_noise
      scan_noise newton_rings reticulation gate_weave lens_ghosting anamorphic_flare
    ].freeze,
    strength: (0.48..0.88)
  }
}.freeze

RANDOM_LANE_NAMES = RANDOM_LANES.keys.freeze

def random_lane(rng) = RANDOM_LANE_NAMES.sample(random: rng)

# One or two steps carry the look and the rest are barely there.
#
# Nine effects at half strength each is mud, and it is the clearest tell of an
# amateur stack: everything turned up, nothing decided. A grade has a subject.
RANDOM_LEADS = (1..2)
# Every chain shapes the light, because a chain that leaves the light alone is
# a chain about texture, and texture is the shallow half of a photograph. One
# of these runs in every picture, and it leads.
RANDOM_SHAPES = %w[relight aerial_depth].freeze

# The wear shelf: dust, scanner noise, tape dropouts, fogged fixer, gate weave.
#
# Off by default, and that is the change. These may not lead — dust and hair at
# 0.94 is the amateur move in a single line, the artefact becoming the picture
# — but the deeper problem is that they are loud by construction. They read as
# an effect where the rest of this file is trying to read as a photograph.
# `--rough` brings them back for the runs that want a handled print, still
# capped and still never leading. A preset is free to disagree; a preset was
# written by somebody.
RANDOM_WEAR = %w[dust_and_hair newton_rings scan_noise gate_weave
                        dodgeburn_artifacts fixing_bath_fog reticulation
                        film_curl_vignette lens_ghosting anamorphic_flare
                        vhs_luma_bleed vhs_chroma_delay vhs_head_switch_band
                        vhs_tracking_noise vhs_interlace_comb
                        crt_phosphor_bloom crt_scanlines minidv_block_dropout
                        hi8_chroma_noise].freeze

# A lead has to read. At 0.38 to 0.66 with supports at 0.05 to 0.16 the stack summed
# to almost nothing and five takes of one frame looked like one take (operator
# review, 2026-10-20), so the leads sit high and the supports are audible.
RANDOM_LEAD_STRENGTH = (0.55..0.9)
RANDOM_SUPPORT_STRENGTH = (0.12..0.28)
# And one step is allowed to disagree with the family, quietly. A chain that is
# only coherent is a template; the interest is in the one thing that should not
# be there, at a strength that makes it a suggestion rather than a joke.
RANDOM_WILDCARD_CHANCE = 0.5

RANDOM_WILDCARD_STRENGTH = (0.1..0.25)
# Heavy mode (--heavy) starts each take from a named look and deals the lanes
# round-robin so one run spans subtle analog to bleeding edge. It is opt-in:
# measured on nine photographs (2026-10-27), 69% of its takes lost the
# source's colour or shapes against 10% of light takes, and its damage rose
# with chain length (53% at 9-11 steps, 100% past 15) and with the strength
# lift it used to apply. A look keeps all its own steps; the random steps grown
# around it stop at HEAVY_MAX_STEPS, and every strength sits in the same band
# as a light take's, since professional practice mixes a look below full
# strength rather than above it.
HEAVY_MAX_STEPS = 10

# Ten takes per photograph in either mode, the top of the constitution's
# five-to-ten range: heavy's lane deal goes round twice and HEAVY_LOOKS has
# eighteen looks, so no two of ten share one. --count sets any other number.
RANDOM_TAKES = 10
HEAVY_LANE_DEAL = %i[
  subtle_analog cinematic_color artistic_analog bleeding_edge_analog bleeding_edge_analog
].freeze

def heavy_mode? = ENV.fetch("POSTPRO_HEAVY", "0") == "1"
# Two marks of wear is a print that has been handled. Five is a prop.
RANDOM_WEAR_CEILING = 2
# A repeat is a second pass, not a second effect: halation twice at different
# radii is what a bright window through a thick base does, and it only means
# anything when the first pass was one of the leads.
RANDOM_DUPLICATE_CHANCE = 0.3
# No two pictures out of one run may be near neighbours. Jaccard over the effect
# sets, with a fresh stock each time.
RANDOM_SIMILARITY_CEILING = 0.34
RANDOM_DRAW_ATTEMPTS = 40

# Effects that can start a chain: not damage, not the backbone, and known to
# some preset, so that the walk has somewhere to go.
# What a chain may draw from. The wear shelf is not in it unless --rough says
# so, and the shape step is appended rather than drawn, so it never has to
# argue with the co-occurrence graph it appears in no preset of.
def random_seeds(lane = nil)
  (random_pool(lane) - random_common_spine) & random_affinity.keys.flatten.uniq
end

def random_pool(lane = nil)
  rough = ARGV.include?("--rough")
  allowed = lane ? RANDOM_LANES.fetch(lane).fetch(:effects) : RECIPE_ALLOWED - [RANDOM_ALWAYS] - RANDOM_SHAPES
  allowed &= RECIPE_ALLOWED
  allowed -= RANDOM_SHAPES
  allowed -= RANDOM_WEAR unless rough || lane == :bleeding_edge_analog || heavy_mode?
  allowed
end

# Which effects a colourist actually puts together, counted off the presets.
def random_affinity
  @random_affinity ||= begin
    pairs = Hash.new(0)
    PRESETS.each_value { |p| Array(p[:fx]).uniq.combination(2) { |a, b| pairs[[a, b].sort] += 1 } }
    pairs
  end
end

# Where each effect belongs in a chain, measured across all eighty-two presets.
#
# A chain in a random order is mush: a print stock before the film curve, a
# vignette before the lens. Rather than declare a stage table that would drift
# from the presets, read the presets — each one is a colourist's ordering, and
# the mean normalised position of an effect across all of them is the order it
# wants to run in. An effect no preset uses sits with the artefacts, late.
def random_stage_rank
  @random_stage_rank ||= begin
    positions = Hash.new { |table, key| table[key] = [] }
    PRESETS.each_value do |p|
      chain = Array(p[:fx])
      chain.each_with_index do |fx, index|
        positions[fx] << (chain.size < 2 ? 0.5 : index.to_f / (chain.size - 1))
      end
    end
    measured = positions.transform_values { |seen| seen.sum / seen.size }
    # The finishing grain is appended after the drawn steps, so it ranks last.
    RECIPE_ALLOWED.to_h { |fx| [fx, measured.fetch(fx, 0.85)] }.merge(RANDOM_ALWAYS => 1.0)
  end
end

# An ordered list of [effect, params] pairs, which is what recipe() iterates. A
# list rather than a hash precisely so an effect can appear twice.
#
# `avoid` holds the chains this run has already drawn. A draw that overlaps one
# of them too far is thrown back, up to a bounded number of attempts, after
# which the least similar of them is used — a run of five pictures that are five
# versions of one picture is the other way to waste somebody's afternoon.
def random_chain(rng = Random.new(postpro_seed), avoid: [], lane: nil)
  closest = nil
  lane = random_lane(rng) if lane.nil?
  RANDOM_DRAW_ATTEMPTS.times do
    picked, wildcard = random_draw(rng, lane:)
    overlap = avoid.map { |other| random_similarity(picked, other.map(&:first)) }.max || 0.0
    return random_finish(picked, wildcard, rng, avoid, lane:) if overlap <= RANDOM_SIMILARITY_CEILING

    closest = [overlap, picked, wildcard] if closest.nil? || overlap < closest.first
  end
  random_finish(closest[1], closest[2], rng, avoid, lane:)
end

# Two chains that share optical_blur, spectral_temp and film_curve share a
# spine, not a look — most presets carry all three. Similarity is measured over
# what is distinctive, meaning the effects fewer than half the presets use, so
# the common backbone stops reading as a resemblance.
def random_similarity(one, two)
  left = random_distinctive(one)
  right = random_distinctive(two)
  return 0.0 if left.empty? || right.empty?

  (left & right).length.to_f / (left | right).length
end

def random_distinctive(names) = names - random_common_spine

# The steps more than half the presets carry: today spectral_temp, film_curve,
# grain and optical_blur.
def random_common_spine
  @random_common_spine ||= begin
    counts = Hash.new(0)
    PRESETS.each_value { |p| Array(p[:fx]).uniq.each { |fx| counts[fx] += 1 } }
    counts.select { |_, n| n > PRESETS.length / 2 }.keys
  end
end

def random_chain_length = RANDOM_CHAIN_LENGTH
