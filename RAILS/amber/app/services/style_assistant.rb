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
#   * It is deterministic for a given user and date. No RNG — the day's
#     Julian number rotates the pick through a taste-ranked shortlist, so
#     refreshing the page shows the same outfit and tomorrow shows a
#     different one.
#   * It rests what you just wore. A garment worn inside REST_DAYS is held
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
    accessory: %w[Accessories]
  }.freeze

  # Offsets keep the zones from rotating in lockstep, so consecutive days
  # differ by more than a wholesale swap.
  ZONE_ROTATION = { outer: 0, top: 1, bottom: 3, dress: 2, shoes: 5, accessory: 7 }.freeze

  # Rotate within the top of each zone. Wider than this and "your best" turns
  # into "anything you own".
  SHORTLIST = 5

  # A garment worn inside this window is rested.
  REST_DAYS = 3

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
      chosen = dress_leads? ? [ pick(:dress), pick(:shoes) ] : [ pick(:top), pick(:bottom), pick(:shoes) ]
      chosen << pick(:outer) if layer?
      chosen << pick(:accessory)
      # Head-to-toe reading order, so the card stacks the way the mannequin does.
      order = ZONES.keys.each_with_index.to_h
      chosen.compact.sort_by { |p| order.fetch(p.zone) }
    end
  end

  def pick(zone)
    shortlist = shortlist_for(zone)
    return nil if shortlist.empty?

    item = shortlist[(date.jd + ZONE_ROTATION.fetch(zone, 0)) % shortlist.size]
    Pick.new(zone: zone, item: item, reasons: reasons_for(zone, item))
  end

  def shortlist_for(zone)
    @shortlists ||= {}
    @shortlists[zone] ||= begin
      pool = candidates.select { |item| ZONES.fetch(zone).include?(item.category) }
      pool = pool.reject { |item| unsuitable?(zone, item) }
      rested = pool.reject { |item| resting?(item) }
      # A thin zone gets its rested garments back rather than disappearing:
      # "no shoes today" is not a styling opinion, it is a bug.
      ranker.rank(rested.presence || pool).first(SHORTLIST)
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

    separates = (ranker.score_for(best_top) + ranker.score_for(best_bottom)) / 2.0
    ranker.score_for(best_dress) > separates
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
