# frozen_string_literal: true

# The shapes behind the analytics page's figures.
#
# The original Amber specification asked to "analyze your wardrobe with
# beautiful information visualization — track usage, cost-per-wear, and
# underutilized items". `WardrobeAnalytics` counts; this turns those counts
# into series a chart can draw, one figure per clause of that sentence:
#
#   category_mix       what the wardrobe is made of
#   wear_distribution  usage — how often garments actually get worn
#   cost_per_wear      the garments costing the most every time they go on
#   idle               underutilized — worn rarely, and how long ago
#
# `share` is normalised against the maximum *within its own series*, so bar
# lengths are comparable inside one figure and meaningless across two.
#
# No label here is a sentence. Every one is a database value or a numeric
# range, and the view supplies the prose through `t()` — otherwise the charts
# would read in English on a Norwegian page.
class WardrobeCharts
  Bar = Data.define(:key, :label, :value, :share, :item) do
    def to_h = { key:, label:, value:, share: }
  end

  # Wear-count buckets, inclusive at both ends; a nil upper bound is the
  # open-ended tail. Keys are stable so the view can name them in either locale.
  WEAR_BUCKETS = [
    [ :never,    0,  0 ],
    [ :"1_2",    1,  2 ],
    [ :"3_5",    3,  5 ],
    [ :"6_10",   6,  10 ],
    [ :"11_20",  11, 20 ],
    [ :"21_plus", 21, nil ]
  ].freeze

  # Ranked figures are a shortlist, not a leaderboard — past eight rows a bar
  # chart stops being read and starts being scrolled.
  TOP_N = 8

  def initialize(user)
    @user = user
  end

  def figures
    {
      category_mix: category_mix,
      wear_distribution: wear_distribution,
      cost_per_wear: cost_per_wear,
      idle: idle
    }
  end

  # What the active wardrobe is made of. Released and boxed garments are left
  # out: this figure answers "what can I wear", not "what have I ever owned".
  def category_mix
    counts = Hash.new(0)
    active.each { |item| counts[item.category.presence] += 1 }

    series(counts.sort_by { |category, count| [ -count, category.to_s ] }.map do |category, count|
      { key: category || "unsorted", label: category, value: count }
    end)
  end

  # Usage. A wardrobe with a tall never-worn column and a short tail is the
  # shape the whole declutter loop exists to correct, and it is invisible in
  # an average.
  def wear_distribution
    series(WEAR_BUCKETS.map do |key, low, high|
      { key: key, label: bucket_label(low, high), value: active.count { |item| in_bucket?(item.times_worn.to_i, low, high) } }
    end)
  end

  # Worst value first — the point of cost-per-wear is to name the expensive
  # garment worn twice, not to celebrate the cheap one worn daily.
  def cost_per_wear
    ranked = active.filter_map { |item| [ item, item.cost_per_wear ] if item.cost_per_wear }
                   .sort_by { |item, cpw| [ -cpw, item.id ] }
                   .first(TOP_N)

    series(ranked.map { |item, cpw| { key: item.id, label: item.title, value: cpw, item: item } })
  end

  # Underutilized: worn fewer than three times, ranked by how long they have
  # been sitting. Idle time is measured from the last wear, falling back to
  # purchase and then to the day the garment entered the wardrobe, so a
  # never-worn garment still has an age.
  def idle
    today = Date.current
    # in_rotation, not active: this figure asks you to go wear something, and a
    # garment in the declutter box is one you have already decided about. The
    # three figures above are inventory questions, so they still count it.
    ranked = user.items.in_rotation.select(&:underused?)
                   .sort_by { |item| [ -idle_days(item, today), item.times_worn.to_i, item.id ] }
                   .first(TOP_N)

    series(ranked.map { |item| { key: item.id, label: item.title, value: idle_days(item, today), item: item } })
  end

  def idle_days(item, today = Date.current)
    since = item.last_worn_on || item.purchase_date || item.created_at&.to_date
    return 0 if since.blank?

    (today - since).to_i.clamp(0, 3650)
  end

  private

  attr_reader :user

  def active = @active ||= user.items.active_wardrobe.to_a

  def series(rows)
    max = rows.filter_map { |row| row[:value] }.max.to_f

    rows.map do |row|
      Bar.new(
        key: row[:key],
        label: row[:label],
        value: row[:value],
        share: max.positive? ? (row[:value] / max).round(4) : 0.0,
        item: row[:item]
      )
    end
  end

  def in_bucket?(worn, low, high)
    high.nil? ? worn >= low : worn.between?(low, high)
  end

  def bucket_label(low, high)
    return low.to_s if low == high
    return "#{low}+" if high.nil?

    "#{low}–#{high}"
  end
end
