# frozen_string_literal: true

# Grow from one effect, admitting only what some preset puts beside all of it.
def random_draw(rng, lane:)
  pool = random_pool(lane)
  target = rng.rand(random_chain_length)
  # Seeded on something that could be the subject, and that can grow. Starting
  # from an artefact grows a chain of nothing but damage — reticulation into
  # fixing-bath fog into gate weave — and then something has to lead it, and dust
  # does. Starting from an effect no preset uses grows nothing at all: five of the
  # seventy-three have no affinity with anything, and seeding on one of those
  # rendered a picture whose whole grade was dual_base_density and grain. They
  # stay reachable as the wildcard, which is where a stranger belongs.
  seeds = random_seeds(lane)
  seeds = pool if seeds.empty?
  analog_pool = pool & (RANDOM_ANALOG_CORE - [RANDOM_ALWAYS])

  # Start with a seed plus two analog steps that are pairwise supported by the
  # observed preset graph. Adding arbitrary analog steps here broke the same
  # co-occurrence invariant the growth loop below enforces.
  picked = nil
  seeds.shuffle(random: rng).each do |seed|
    pairs = (analog_pool - [seed]).combination(2).select do |left, right|
      [[seed, left], [seed, right], [left, right]].all? do |a, b|
        random_affinity[[a, b].sort].positive?
      end
    end
    next if pairs.empty?

    picked = [seed, *pairs.sample(random: rng)]
    break
  end

  picked ||= [seeds.sample(random: rng)]
  2.times do
    analog = (analog_pool - picked).select do |candidate|
      picked.all? { |held| random_affinity[[candidate, held].sort].positive? }
    end.sample(random: rng)
    picked << analog if analog
  end
  while picked.length < target
    admissible = (pool - picked).select do |candidate|
      next false if RANDOM_WEAR.include?(candidate) &&
                    (picked & RANDOM_WEAR).length >= RANDOM_WEAR_CEILING

      picked.all? { |held| random_affinity[[candidate, held].sort].positive? }
    end
    break if admissible.empty?

    picked << admissible.sample(random: rng)
  end
  wildcard = rng.rand < RANDOM_WILDCARD_CHANCE ? (pool - picked).sample(random: rng) : nil
  [picked + [wildcard].compact + [RANDOM_SHAPES.sample(random: rng)], wildcard]
end

def random_finish(picked, wildcard, rng, avoid = [], lane: random_lane(rng))
  # Nor is the backbone the subject. optical_blur, spectral_temp and film_curve
  # are in most presets because most pictures want a little of each; leading
  # with optical_blur at 0.95 is not a look, it is an out-of-focus photograph.
  candidates = picked - [wildcard] - RANDOM_WEAR - random_common_spine
  candidates = picked - [wildcard] if candidates.empty?
  # The shape step is one of the leads, not an extra one: three leads is three
  # things asking to be looked at.
  shaping = picked & RANDOM_SHAPES
  leads = shaping | candidates.sample(rng.rand(RANDOM_LEADS) - shaping.length, random: rng)
  # A second pass belongs a quarter of the way further along the process, not at
  # the end and not next to the first: two adjacent passes of one effect are
  # just one stronger pass, and the interest is in what happened in between.
  # Never the shape step. Relighting twice in a row is relighting once, harder,
  # and the whole argument for a repeat is what happens between the passes.
  repeatable = leads - RANDOM_SHAPES
  repeat = repeatable.sample(random: rng) if repeatable.any? && rng.rand < RANDOM_DUPLICATE_CHANCE
  keyed = picked.map { |fx| [fx, random_stage_rank[fx], rng.rand] }
  keyed << [repeat, [random_stage_rank[repeat] + 0.25, 1.0].min, rng.rand] if repeat
  ordered = keyed.sort_by { |_, rank, jitter| [rank, jitter] }.map(&:first)
  seen = Hash.new(0)
  chain = ordered.map do |fx|
    repeat = (seen[fx] += 1) > 1
    band = if repeat || fx == wildcard then wildcard_or_repeat_strength(fx, wildcard)
           elsif leads.include?(fx) then RANDOM_LEAD_STRENGTH
           else RANDOM_SUPPORT_STRENGTH
           end
    [fx, (band.first + rng.rand * (band.last - band.first)).round(2)]
  end
  band = RANDOM_LANES.fetch(lane).fetch(:strength)
  chain << [RANDOM_ALWAYS, { "intensity" => (band.first + rng.rand * (band.last - band.first)).round(2),
                             "stock" => random_stock(rng, avoid).to_s }]
end

# A repeat is a lighter second pass; a wildcard is a suggestion. Same band.
def wildcard_or_repeat_strength(_fx, _wildcard) = RANDOM_WILDCARD_STRENGTH

# A fresh emulsion per picture while there are any left unused this run.
def random_stock(rng, avoid)
  spent = avoid.filter_map { |chain| chain.last&.last }
               .filter_map { |params| params.is_a?(Hash) ? params["stock"] : nil }
  (STOCKS.keys - spent.map(&:to_sym)).then { |left| left.empty? ? STOCKS.keys : left }
                                     .sample(random: rng)
end

def random_chain_name(chain)
  chain.map { |fx, _| fx }.tally.map { |fx, n| n > 1 ? "#{fx}x#{n}" : fx }.join("-")
end

# Looks that commit. A heavy take starts from one of these named presets at full
# strength, so five takes of one frame differ in what they decided and not only in
# how much they changed it. They span stocks and colour worlds on purpose.
HEAVY_LOOKS = %i[
  noir neon_night tokyo_night bleached magic_hour kodachrome_look technicolor_3strip
  cross_process cyanotype_look infrared_look cinematic blockbuster golden_age
  day_for_night process_e6 reversal dream silver_gelatin
].freeze

# A preset written as the ordered recipe the random chains speak, so a look can be
# merged with drawn steps. Effects the recipe vocabulary lacks are dropped.
def preset_as_recipe(name)
  data = PRESETS.fetch(name.to_sym)
  stock = (data[:stock] || :kodak_portra).to_s
  intensity = (data[:intensity] || 0.8).to_f.clamp(0.3, 1.0)
  Array(data[:fx]).map(&:to_s).uniq.filter_map do |fx|
    next unless RECIPE_ALLOWED.include?(fx)

    [fx, look_step_params(data, fx, intensity, stock)]
  end
end

# Everything the preset tells its own steps, so a look-led take runs the look as
# the preset does: its stops, exposure time, print stock, lens and age, not
# only its intensity and stock.
def look_step_params(data, fx, intensity, stock)
  params = { "intensity" => intensity, "stock" => stock }
  params["target_kelvin"] = data[:temp].to_f if fx == "spectral_temp" && data[:temp]
  params["kelvin"] = data[:temp].to_f if fx == "color_temp" && data[:temp]
  params["stops"] = data[:stops].to_f if fx == "push_pull" && data[:stops]
  params["exposure_seconds"] = data[:exposure_secs].to_f if fx == "reciprocity_failure" && data[:exposure_secs]
  params["print_stock"] = data[:print_stock].to_s if fx == "print_film" && data[:print_stock]
  params["lens"] = data[:lens].to_s if fx == "vintage_lens" && data[:lens]
  params["age"] = data[:age].to_f if data[:age] && %w[faded_print dye_fade expired_film].include?(fx)
  params["tonemap"] = data[:tonemap].to_s if fx == "tonemap" && data[:tonemap]
  params
end

# Each take must differ from the last in kind. The next look is drawn from the
# ones not yet used, on a stock no earlier take used, and a repeat of either is the
# last resort once the families run out.
def next_heavy_look(rng, used)
  stocks = used.map { |look| PRESETS.fetch(look)[:stock] }
  fresh = (HEAVY_LOOKS - used).shuffle(random: rng)
  fresh.find { |look| !stocks.include?(PRESETS.fetch(look)[:stock]) } || fresh.first || HEAVY_LOOKS.sample(random: rng)
end

# The look's own steps, then the strongest few steps of a random chain of light,
# texture and wear, up to HEAVY_MAX_STEPS in all, in physical order with one
# grain pass last.
# A look's own steps, less the unclean ones unless --rough admits them.
def clean_look_steps(look)
  steps = preset_as_recipe(look)
  ARGV.include?("--rough") ? steps : steps.reject { |step| RANDOM_UNCLEAN.include?(step.first) }
end

def look_led_chain(rng, look:, avoid: [], lane: nil)
  base = clean_look_steps(look)
  taken = base.map(&:first)
  drawn = random_chain(rng, avoid:, lane:).reject { |fx, _| taken.include?(fx) || fx == RANDOM_ALWAYS }
  # One step of the cap is always the closing grain pass.
  tail = strongest_steps(drawn, HEAVY_MAX_STEPS - 1 - base.count { |fx, _| fx != RANDOM_ALWAYS })

  stock = (PRESETS.fetch(look.to_sym)[:stock] || :kodak_portra).to_s
  grain = base.find { |fx, _| fx == RANDOM_ALWAYS } || [RANDOM_ALWAYS, { "intensity" => 0.6, "stock" => stock }]
  rank = random_stage_rank
  body = (base.reject { |fx, _| fx == RANDOM_ALWAYS } + tail)
         .each_with_index.sort_by { |(fx, _), index| [rank.fetch(fx, 0.85), index] }.map(&:first)
  body << grain
end

# The `room` strongest steps of a drawn chain, in their drawn order.
def strongest_steps(chain, room)
  return [] unless room.positive?

  kept = chain.each_with_index.max_by(room) { |(_, params), _| params.is_a?(Numeric) ? params : params["intensity"].to_f }
  kept.sort_by(&:last).map(&:first)
end

# A random take is named for what it is: its place in the run, the look it was
# built on, and the lane it was dealt. The number keeps one family's takes apart
# and in draw order; the dealt lane is named over the inferred one, which can
# read a bleeding-edge take as subtle. Without a take the chain stays in the
# name, which separates one-off random grades of the same photograph.
def random_take_label(chain, take = nil)
  lane = (take&.lane || random_chain_lane(chain)).to_s

  return "#{lane}_#{random_chain_name(chain)[0, 50]}" unless take

  [format("%02d", take.number), take.look, lane].compact.join("_")
end

# One take of a random run: its place in the run, the named look it was built
# on (nil outside heavy mode), and the lane it was dealt. It names the file and
# goes into the sidecar; every caller outside a random run leaves it out.
RandomTake = Data.define(:number, :look, :lane)

def random_chain_lane(chain)
  effects = chain.map(&:first).map(&:to_s)
  RANDOM_LANES.max_by do |_name, spec|
    (effects & spec.fetch(:effects)).uniq.length
  end&.first || :subtle_analog
end
