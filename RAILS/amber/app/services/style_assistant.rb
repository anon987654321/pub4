# frozen_string_literal: true

# One outfit, for today, from what you already own.
#
# The original Amber specification asked for a Style Assistant that gives
# "daily outfit suggestions that make you look your best". `OutfitGeneration`
# is the wrong tool for that: it persists an Outfit and a Recommendation on
# every call, so putting it on the dashboard would have manufactured a record
# per page load. This one suggests and commits nothing until you say so.
#
# Two properties make it a *daily* suggestion rather than a shuffle:
#
#   * It is deterministic for a given user and date. No RNG — a small
#     set of near-best combinations is ranked by taste and outfit compatibility,
#     then the day's Julian number rotates through that set.
#   * It rests what you wore. A garment worn inside REST_DAYS is held
#     back unless its zone would otherwise be empty.
#
# Weather arrives as a parameter, never fetched here — the dashboard already
# has it, and a service that reached for the network on every render would
# put an HTTP round trip in front of the front page.
class StyleAssistant
  Pick = Data.define(:zone, :item, :reasons)
  Suggestion = Data.define(:date, :picks, :notes) do
    def items = picks.map(&:item)
    def any? = picks.any?
    def item_ids = items.map(&:id)
  end

  # Head to toe. A dress replaces top and bottom rather than joining them.
  ZONES = {
    outer: %w[Outerwear],
    top: %w[Tops],
    bottom: %w[Bottoms],
    dress: %w[Dresses],
    shoes: %w[Shoes],
    accessory: %w[Accessories],
  }.freeze

  # Rotate within the top of each zone. Wider than this and "your best" turns
  # into "anything you own".
  SHORTLIST = 5

  # A garment worn inside this window is rested.
  REST_DAYS = 3

  # Keep daily looks from becoming static while avoiding visibly weaker outfits.
  COMPOSITION_TOLERANCE = 0.025

  COLD_C = 10
  WARM_C = 20
  WET = /rain|snow|shower|thunder/i
  DELICATE_SHOES = /suede|shearling|satin|silk/i
  LIGHT_MATERIALS = /linen|cotton|silk|viscose/i

  def initialize(user, weather: nil, date: Date.current)
    @user = user
    @weather = weather
    @date = date
  end

  def suggest
    Suggestion.new(date: date, picks: picks, notes: notes)
  end

  private

  attr_reader :user, :weather, :date

  def picks
    @picks ||= begin
      zones = dress_leads? ? %i[dress shoes] : %i[top bottom shoes]
      zones << :outer if layer?
      zones << :accessory
      choose_composition(zones)
    end
  end

  # Select from complete looks, not independent best-per-zone picks. Each zone
  # is bounded to SHORTLIST candidates, so even a five-zone look evaluates at
  # most 3,125 combinations and writes no Outfit or Recommendation records.
  def choose_composition(zones)
    zone_picks = zones.filter_map do |zone|
      items = shortlist_for(zone)
      next if items.empty?

      items.map { |item| Pick.new(zone:, item:, reasons: reasons_for(zone, item)) }
    end
    return [] if zone_picks.empty?

    # Enumerate the Cartesian product lazily and retain only the leading shortlist.
    # Increasing the best score can only narrow the tolerance window, so an entry
    # discarded from the top five can never become eligible again.
    finalists = []
    best_score = nil

    zone_picks.first.product(*zone_picks.drop(1)) do |composition|
      score = composition_score(composition)
      if best_score.nil? || score > best_score
        best_score = score
        minimum_score = best_score - COMPOSITION_TOLERANCE
        finalists.reject! { |candidate_score, _candidate| candidate_score < minimum_score }
      end

      next if score < best_score - COMPOSITION_TOLERANCE

      finalists << [ score, composition ]
      finalists.sort_by! { |candidate_score, candidate| [ -candidate_score, candidate.map { |pick| pick.item.id } ] }
      finalists.pop if finalists.size > SHORTLIST
    end

    selected = finalists.fetch(date.jd % finalists.length).last
    order = ZONES.keys.each_with_index.to_h
    selected.sort_by { |pick| order.fetch(pick.zone) }
  end

  # Scores are facts about a garment within this one suggestion. Reuse them
  # across ranking and combination scoring: a five-zone, five-candidate look
  # otherwise re-scores each garment hundreds of times.
  def taste_score(item)
    @taste_scores ||= {}
    key = item.id || item.object_id
    @taste_scores.fetch(key) { @taste_scores[key] = ranker.score_for(item) }
  end

  def composition_score(composition)
    items = composition.map(&:item)
    taste = items.sum { |item| taste_score(item) } / items.size.to_f
    compatibility = compatibility_ranker.score_items(items, weather: compatibility_weather)
    (taste * 0.65 + compatibility * 0.35).round(4)
  end

  def compatibility_ranker = @compatibility_ranker ||= OutfitCompatibility.new(user)

  def compatibility_weather
    return "rain" if wet?
    return "cold" if cold?
    return "warm" if warm?

    nil
  end

  def shortlist_for(zone)
    @shortlists ||= {}
    @shortlists[zone] ||= begin
      pool = candidates.select { |item| ZONES.fetch(zone).include?(item.category) }
      pool = pool.reject { |item| unsuitable?(zone, item) }
      rested = pool.reject { |item| resting?(item) }
      # A thin zone gets its rested garments back rather than disappearing:
      # "no shoes today" is not a styling opinion, it is a bug.
      ranker.rank(rested.presence || pool, scorer: method(:taste_score)).first(SHORTLIST)
    end
  end

  # in_rotation, not active_wardrobe: putting a garment you have already boxed
  # on today's outfit is the opposite of the job.
  def candidates
    @candidates ||= user.items.in_rotation.to_a.reject { |item| out_of_season?(item) }
  end

  def ranker = @ranker ||= TasteRanker.new(user)

  def out_of_season?(item)
    season = item.season.to_s
    season.present? && season != "All-Season" && season != item.current_season
  end

  def resting?(item)
    item.last_worn_on.present? && item.last_worn_on > date - REST_DAYS
  end

  # Weather vetoes, applied before taste: no ranking makes suede the right
  # answer in the rain.
  def unsuitable?(zone, item)
    zone == :shoes && wet? && item.material.to_s.match?(DELICATE_SHOES)
  end

  # A dress leads when the wardrobe's best dress out-ranks its best top —
  # a deterministic comparison, not a coin toss.
  def dress_leads?
    best_dress = shortlist_for(:dress).first
    return false if best_dress.nil?

    best_top = shortlist_for(:top).first
    best_bottom = shortlist_for(:bottom).first
    return true if best_top.nil? || best_bottom.nil?

    separates = (taste_score(best_top) + taste_score(best_bottom)) / 2.0
    taste_score(best_dress) > separates
  end

  def layer? = cold? || wet?

  def temp = weather && weather[:temp]
  def cold? = temp.present? && temp < COLD_C
  def warm? = temp.present? && temp > WARM_C
  def wet? = weather && weather[:description].to_s.match?(WET)

  # Weather reasons are symbols the view translates; TasteRanker's are prose it
  # prints verbatim, the same split the rest of the coach surfaces already use.
  def reasons_for(zone, item)
    [
      (:weatherproof if zone == :outer && layer?),
      (:light_fabric if warm? && item.material.to_s.match?(LIGHT_MATERIALS)),
      *ranker.explain(item)
    ].compact.first(3)
  end

  # Why today looks like this. The weather line itself is not repeated here —
  # the dashboard already prints it above the card.
  def notes
    [
      (:layering if layer?),
      (:no_outerwear if warm?),
      (:resting if rested_anything?)
    ].compact
  end

  def rested_anything?
    candidates.any? { |item| resting?(item) }
  end
end
