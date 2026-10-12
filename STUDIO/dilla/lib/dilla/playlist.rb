class Bag
  def initialize(items, rng, state = nil)
    @items = items
    @rng = rng
    @remaining = (state&.fetch('remaining', nil) || []).select { |i| items.include?(i) }
    @last = state&.fetch('last', nil)
  end

  def draw
    if @remaining.empty?
      @remaining = @items.shuffle(random: @rng)
      @remaining.rotate! if @remaining.size > 1 && @remaining.first == @last
    end
    @last = @remaining.shift
  end

  def position = "#{@items.size - @remaining.size}/#{@items.size}"

  def to_h = { 'remaining' => @remaining, 'last' => @last }
end

# What each pass draws, every kind from its own bag: the progression from the whole array, the
# mode, the arp or repeat style, the voice family, a patch of that family, the treatment.
class Playlist
  MODES = %w[arp repeat pad].freeze

  def initialize(data, rng, state = {}, pool: 'essential')
    @data = data
    @pool = pool
    @rng = rng
    @state = state
    @bags = {}
  end

  def bag(key, items)
    @bags[key] ||= Bag.new(items, @rng, @state[key])
  end

  # The progressions --play draws from: the essential staples, or the whole array.
  def progression_pool
    @pool == 'all' ? (0...@data.fetch('progressions').size).to_a : @data.fetch('essential')
  end

  def voices_by_family = @data.fetch('voices').group_by { |_, v| v.fetch('family') }.transform_values { |rows| rows.map(&:first) }

  def draw(fixed = {})
    index = bag('progressions', progression_pool).draw
    position = @bags['progressions'].position
    mode = fixed[:mode] || bag('modes', MODES).draw
    style = case mode
            when 'arp' then bag('styles:arp', @data.dig('arp', 'play_styles')).draw
            when 'repeat' then bag('styles:repeat', @data.fetch('comp').fetch('styles').keys).draw
            end
    families = voices_by_family
    voice = fixed[:voice] || begin
      family = bag('families', families.keys.sort).draw
      bag("patches:#{family}", families.fetch(family).sort).draw
    end
    profile = fixed[:profile] || bag('profiles', @data.fetch('play_profiles')).draw
    { prog: index, position:, mode:, style:, voice:, profile: }
  end

  def to_h = @bags.transform_values(&:to_h)
end

# Never stops: each pass draws from the playlist, renders while the one before plays, and
# plays it when that ends. Two files alternate, so the one being played is never the one being
# written; the bags are saved beside them, so a restart goes on with the cycle.
