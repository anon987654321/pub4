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

# A bag whose neighbours never share a key: the order of each cycle is a shuffle in which no two
# items side by side, and not the first after the last of the cycle before, have the same key.
# The state keeps the last item, so a restart goes on from it.
class SpacedBag < Bag
  TRIES = 200

  def initialize(items, rng, state = nil, key:)
    super(items, rng, state)
    @key = key
  end

  def draw
    @remaining = arrangement if @remaining.empty?
    @last = @remaining.shift
  end

  private

  def arrangement
    before = @last && @key.call(@last)
    TRIES.times do
      order = @items.shuffle(random: @rng)
      return order if spaced?(order, before)
    end
    greedy(before)
  end

  def spaced?(order, before) = order.first.then { |first| @key.call(first) != before } && order.each_cons(2).none? { |a, b| @key.call(a) == @key.call(b) }

  # When a shuffle never works (one key holds more than half the items) the key with the most
  # left goes next, so the repeats come as far apart as they can.
  def greedy(before)
    pool = @items.shuffle(random: @rng).group_by(&@key)
    order = []
    until pool.empty?
      pick = pool.reject { |key, _| key == before }.max_by { |_, rows| rows.size } || pool.first
      before = pick.first
      order << pick.last.shift
      pool.delete(before) if pick.last.empty?
    end
    order
  end
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

  def bag(key, items, spaced_by: nil)
    @bags[key] ||= spaced_by ? SpacedBag.new(items, @rng, @state[key], key: spaced_by) : Bag.new(items, @rng, @state[key])
  end

  # The progressions --play draws from: the essential staples, or the whole array.
  def progression_pool
    @pool == 'all' ? (0...@data.fetch('progressions').size).to_a : @data.fetch('essential')
  end

  def voices_by_family = @data.fetch('voices').group_by { |_, v| v.fetch('family') }.transform_values { |rows| rows.map(&:first) }

  def family_of(voice) = @data.fetch('voices').fetch(voice).fetch('family')

  # The next voice from the one bag that holds every patch of every family: a patch comes back only
  # after all the others have played, and a family never follows itself.
  def next_voice = bag('voices', @data.fetch('voices').keys.sort, spaced_by: method(:family_of)).draw

  # `count` voices in a row, one for each chord of a pad, from the same bag.
  def voices_for(count) = Array.new(count) { next_voice }

  def draw(fixed = {})
    index = bag('progressions', progression_pool).draw
    position = @bags['progressions'].position
    mode = fixed[:mode] || bag('modes', MODES).draw
    style = case mode
            when 'arp' then bag('styles:arp', @data.dig('arp', 'play_styles')).draw
            when 'repeat' then bag('styles:repeat', @data.fetch('comp').fetch('styles').keys).draw
            end
    voices = fixed[:patch_per_chord] && mode == 'pad' && !fixed[:voice] ? voices_for(@data.fetch('progressions').fetch(index).size) : nil
    voice = fixed[:voice] || voices&.first || next_voice
    profile = fixed[:profile] || bag('profiles', @data.fetch('play_profiles')).draw
    kit = bag('kits', @data.fetch('kits').keys).draw
    drums = bag('drums', @data.fetch('drum_patterns').keys).draw
    { prog: index, position:, mode:, style:, voice:, voices:, bag: bag_position('voices'), profile:, kit:, drums: }
  end

  def bag_position(key) = @bags[key]&.position

  def to_h = @bags.transform_values(&:to_h)
end

# Never stops: each pass draws from the playlist, renders while the one before plays, and
# plays it when that ends. Two files alternate, so the one being played is never the one being
# written; the bags are saved beside them, so a restart goes on with the cycle.
