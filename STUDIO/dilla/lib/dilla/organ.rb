# frozen_string_literal: true

# ------------------------------------------------------------------ organ
# A generative improvisation for organ in the manner of the baroque: a pedal line, inner voices
# that hold and resolve suspensions, and a right hand that runs, turns and trills over them, in
# phrases of two to four bars that end on cadences. Everything is a step of one declared scale,
# counted as an integer index into it, so no note can leave the scale; the harmony is the scale's
# own triads. The same seed plays the same piece. Time is in sixteenths, sixteen to the bar, and
# the sound is the organ voice with a registration for each line, the right hand's rotating from
# phrase to phrase.
module Organ
  BAR = 16
  FLATS = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
  TRIAD = { [3, 7] => 'm', [4, 7] => '', [3, 6] => 'dim', [4, 8] => 'aug' }.freeze
  CADENCE = { 'authentic' => [4, 0], 'half' => [3, 4], 'deceptive' => [4, 5], 'plagal' => [3, 0] }.freeze
  MOVES = { 0 => [3, 5, 1], 1 => [4, 3], 2 => [5, 3], 3 => [1, 4, 0], 4 => [0, 5], 5 => [1, 3, 4], 6 => [0] }.freeze
  # A suspension holds a note of the chord before into the next, where it is a dissonance over the
  # bass, and lets it fall a step on the third beat. 4-3 and 9-8 sit over the root, 7-6 over the
  # chord's third. The numbers are scale steps above the chord's root.
  SUSPENSION = { '4-3' => { held: 3, resolved: 2, bass: 0 }, '9-8' => { held: 8, resolved: 7, bass: 0 },
                 '7-6' => { held: 8, resolved: 7, bass: 2 } }.freeze

  Note = Struct.new(:step, :length, :midi, :gain, :phrase)
  Phrase = Struct.new(:first_bar, :bars, :cadence, :registration) do
    def last_bar = first_bar + bars - 1
  end
  Suspension = Struct.new(:type, :held, :resolved, :bass)
  Piece = Struct.new(:key, :scale, :pcs, :names, :phrases, :lines, :suspensions, keyword_init: true) do
    def steps = names.size * BAR
  end

  # The scale as an infinite ladder: index 0 is the tonic in the lowest octave, 7 the tonic an
  # octave above. Triads, neighbours and runs are arithmetic on the index.
  class Ladder
    def initialize(tonic, intervals)
      @tonic = tonic
      @intervals = intervals
    end

    def midi(idx) = 24 + @tonic + (12 * idx.div(7)) + @intervals[idx % 7]

    def pcs = @intervals.map { |i| (@tonic + i) % 12 }

    def pc(idx) = midi(idx) % 12

    # Every index whose note lies in a midi range, lowest first.
    def within(range) = (-7..28).select { |i| range.cover?(midi(i)) }

    def chord_tone?(idx, degree) = [0, 2, 4].include?((idx - degree) % 7)

    # The name of the triad on a degree, as Chords reads it.
    def chord_name(degree)
      root = pc(degree)
      quality = TRIAD.fetch([(pc(degree + 2) - root) % 12, (pc(degree + 4) - root) % 12]) { raise ArgumentError, "no triad on degree #{degree}" }
      "#{FLATS[root]}#{quality}"
    end

    # The index in the range, of the given degree (or of a tone of the chord on it) nearest to `near`.
    def nearest(degree, near, range) = within(range).select { |i| i % 7 == degree % 7 }.min_by { |i| [(i - near).abs, i] }

    def nearest_tone(degree, near, range) = within(range).select { |i| chord_tone?(i, degree) }.min_by { |i| [(i - near).abs, i] }

    def closest_to_midi(midi, range) = within(range).min_by { |i| [(self.midi(i) - midi).abs, i] }
  end

  def self.rng(seed, label) = Random.new(Zlib.crc32("#{seed}:organ:#{label}"))

  def self.pick(table, rng)
    roll = rng.rand * table.values.sum
    table.each { |name, weight| return name if (roll -= weight).negative? }
    table.keys.last
  end

  # ------------------------------------------------------------ the whole piece
  def self.compose(seed:, config:, bars: nil, key: nil, scale: nil)
    bars = (bars || config.fetch('bars')).clamp(4, 96)
    ladder, key_name, scale_name = tonality(seed, config, key, scale)
    phrases = plan_phrases(seed, config, bars)
    degrees = harmony(seed, phrases)
    ranges = config.fetch('ranges').transform_values { |lo, hi| (lo..hi) }
    suspensions = plan_suspensions(seed, config, ladder, degrees, phrases, ranges.fetch('left'))
    lines = { 'pedal' => pedal(seed, config, ladder, degrees, phrases, suspensions, ranges.fetch('pedal')),
              'left' => left(seed, ladder, degrees, phrases, suspensions, ranges.fetch('left')),
              'right' => right(seed, config, ladder, degrees, phrases, ranges.fetch('right')) }
    piece = Piece.new(key: key_name, scale: scale_name, pcs: ladder.pcs, names: degrees.map { |d| ladder.chord_name(d) },
                      phrases:, lines:, suspensions: suspensions.compact.size)
    check(piece, ranges)
    piece
  end

  def self.tonality(seed, config, key, scale)
    rng = rng(seed, 'key')
    scale ||= pick(config.fetch('scale_weights'), rng)
    drawn = rng.rand(12)
    tonic = key ? key_pc(key) : drawn
    [Ladder.new(tonic, config.fetch('scales').fetch(scale) { raise ArgumentError, "no scale #{scale.inspect}" }), FLATS[tonic], scale]
  end

  def self.key_pc(key)
    named = key.to_s.match(/\A([A-G])([b#]?)\z/) or raise ArgumentError, "no key #{key.inspect}"
    (Chords::NOTE_PC.fetch(named[1]) + Chords::ACCIDENTAL.fetch(named[2])) % 12
  end

  # Phrase lengths from two to four bars that add up to the piece; the last ends on an
  # authentic cadence, the others on a half, authentic, deceptive or plagal one.
  def self.plan_phrases(seed, config, bars)
    rng = rng(seed, 'phrases')
    out = []
    first = 0
    while first < bars
      left = bars - first
      options = config.fetch('phrase_bars').select { |n| n <= left && left - n != 1 }
      out << Phrase.new(first, options.sample(random: rng) || left, nil, nil)
      first += out.last.bars
    end
    rotation = config.fetch('rotation')
    out.each_with_index do |phrase, i|
      phrase.cadence = i == out.size - 1 ? 'authentic' : pick(config.fetch('cadences'), rng)
      phrase.registration = rotation[i % rotation.size]
    end
    out
  end

  # One degree for each bar: lead chords that move by the usual roots, then the cadence.
  def self.harmony(seed, phrases)
    rng = rng(seed, 'harmony')
    phrases.each_with_index.flat_map do |phrase, i|
      cadence = CADENCE.fetch(phrase.cadence).dup
      cadence[0] = [1, 3].sample(random: rng) if phrase.cadence == 'half'
      current = i.zero? || rng.rand < 0.7 ? 0 : [5, 3].sample(random: rng)
      lead = Array.new(phrase.bars - cadence.size) do
        chord = current
        current = (MOVES.fetch(current) - [cadence.first]).sample(random: rng) || 0
        chord
      end
      lead + cadence
    end
  end

  # ---------------------------------------------------------------- suspensions
  # A Suspension or nil for each bar. The held note must belong to the chord before it and, when
  # that bar also resolves a suspension, be the very note it resolved to.
  def self.plan_suspensions(seed, config, ladder, degrees, phrases, range)
    rng = rng(seed, 'suspensions')
    spec = config.fetch('suspensions')
    penultimate = phrases.map { |ph| ph.last_bar - 1 }
    plan = Array.new(degrees.size)
    (1...(degrees.size - 1)).each do |bar| # the last bar is the piece's rest and keeps its root
      next unless rng.rand < (penultimate.include?(bar) ? spec.fetch('cadence_chance') : spec.fetch('chance'))

      type = spec.fetch('types').shuffle(random: rng).find do |t|
        held = degrees[bar] + SUSPENSION.fetch(t)[:held]
        ladder.chord_tone?(held, degrees[bar - 1]) && (plan[bar - 1].nil? || plan[bar - 1].resolved % 7 == held % 7)
      end
      next unless type

      row = SUSPENSION.fetch(type)
      near = plan[bar - 1]&.resolved || ladder.closest_to_midi(63, range)
      held = ladder.nearest(degrees[bar] + row[:held], near, (range.first + 5)..range.last)
      plan[bar] = Suspension.new(type, held, held - 1, degrees[bar] + row[:bass])
    end
    plan
  end

  # ---------------------------------------------------------------------- pedal
  # The root on the strong beats: whole bars of half notes, or a walk of quarters with a
  # neighbour on the second and an approach to the next root on the fourth; a tonic held through the
  # lead bars of some phrases; the last bar of a phrase a long root.
  def self.pedal(seed, config, ladder, degrees, phrases, suspensions, range)
    rng = rng(seed, 'pedal')
    notes = []
    last = 42
    lows = ladder.within(range)
    root_near = lambda do |degree|
      lows.select { |i| i % 7 == degree % 7 }.min_by { |i| [(ladder.midi(i) - last).abs, i] }
    end
    put = lambda do |bar, offset, length, idx, phrase|
      last = ladder.midi(idx)
      notes << Note.new((bar * BAR) + offset, length, last, 0.9, phrase)
    end
    phrases.each_with_index do |phrase, p|
      lead = phrase.bars - 2
      point = lead >= 1 && rng.rand < config.fetch('pedal_point_chance')
      put.call(phrase.first_bar, 0, lead * BAR, root_near.call(0), p) if point
      (phrase.first_bar..phrase.last_bar).each do |bar|
        next if point && bar < phrase.first_bar + lead

        sus = suspensions[bar]
        root = root_near.call(sus && sus.bass % 7 != degrees[bar] ? sus.bass : degrees[bar])
        if bar == phrase.last_bar
          put.call(bar, 0, bar == degrees.size - 1 ? BAR : 12, root, p)
        elsif sus || pick(config.fetch('pedal_styles'), rng) == 'half'
          put.call(bar, 0, 8, root, p)
          put.call(bar, 8, 8, root, p)
        else
          neighbour = lows.include?(root + 1) ? root + 1 : root - 1
          follow = lows.select { |i| i % 7 == degrees[bar + 1] % 7 }.min_by { |i| [(ladder.midi(i) - ladder.midi(root)).abs, i] }
          approach = follow + (root > follow ? 1 : -1)
          put.call(bar, 0, 4, root, p)
          put.call(bar, 4, 4, neighbour, p)
          put.call(bar, 8, 4, root, p)
          put.call(bar, 12, 4, lows.include?(approach) && approach != root ? approach : neighbour, p)
        end
      end
    end
    notes
  end

  # ------------------------------------------------------------------- left hand
  # Two inner voices. The alto goes by half bars, quarters or the off-beat eighths of a continuo;
  # where a suspension is planned it holds the note tied from the bar before and falls a step on the
  # third beat. The tenor sounds another tone of the chord, clear of the suspended note.
  def self.left(seed, ladder, degrees, phrases, suspensions, range)
    rng = rng(seed, 'left')
    upper = ((range.first + 9)..range.last)
    lower = (range.first..(range.first + 8))
    alto = []
    tenor = []
    a_last = ladder.closest_to_midi(63, upper)
    t_last = ladder.closest_to_midi(55, lower)
    style = nil
    degrees.each_index do |bar|
      p = phrases.index { |ph| bar <= ph.last_bar }
      style = %w[sustained quarters continuo].sample(random: rng) if bar == phrases[p].first_bar
      sus = suspensions[bar]
      after = suspensions[bar + 1]
      degree = degrees[bar]
      base = bar * BAR
      clash = lambda do |idx|
        sus && ((ladder.midi(idx) - ladder.midi(sus.held)).abs <= 1 || idx % 7 == sus.held % 7)
      end
      tone = lambda do |near, band|
        pool = ladder.within(band).select { |i| ladder.chord_tone?(i, degree) }
        clear = pool.reject { |i| clash.call(i) }
        (clear.empty? ? pool : clear).min_by { |i| [(i - near).abs, i] }
      end
      low = tone.call(t_last, lower)
      if sus
        alto.last.length += 8
        alto << Note.new(base + 8, 8, ladder.midi(sus.resolved), 0.7, p)
        a_last = sus.resolved
      elsif bar == degrees.size - 1
        alto << Note.new(base, BAR, ladder.midi(tone.call(a_last, upper)), 0.7, p)
      else
        first = tone.call(a_last, upper)
        second = after ? after.held : tone.call(first + (rng.rand < 0.5 ? 1 : -1), upper)
        alto.concat(style_notes(style, base, first, second, p, ladder))
        a_last = second
      end
      if bar == degrees.size - 1
        tenor << Note.new(base, BAR, ladder.midi(low), 0.7, p)
      else
        tenor.concat(style_notes(style, base, low, tone.call(low + (rng.rand < 0.5 ? 1 : -1), lower), p, ladder))
      end
      t_last = low
    end
    (alto + tenor).sort_by { |n| [n.step, n.midi] }
  end

  # One bar of an inner voice: held half bars, quarters, or the off-beat eighths of a continuo.
  # Every style ends on `second`, which is what a tied suspension takes up.
  def self.style_notes(style, base, first, second, phrase, ladder)
    case style
    when 'quarters'
      [first, second, first, second].each_with_index.map { |idx, k| Note.new(base + (k * 4), 4, ladder.midi(idx), 0.7, phrase) }
    when 'continuo'
      [Note.new(base, 2, ladder.midi(first), 0.7, phrase)] +
        [[2, first], [6, first], [10, second], [14, second]].map { |off, idx| Note.new(base + off, 2, ladder.midi(idx), 0.55, phrase) }
    else
      [Note.new(base, 8, ladder.midi(first), 0.7, phrase), Note.new(base + 8, 8, ladder.midi(second), 0.7, phrase)]
    end
  end

  # ------------------------------------------------------------------ right hand
  # Built from arrivals, a chord tone at the start of every half bar, drawn along an arch that
  # climbs through the phrase and comes down onto the cadence. Between two arrivals one figure
  # decorates the step: a run, a turn, a neighbour, an appoggiatura, a dotted walk, the phrase's
  # motif or the motif a step along, or a trill on the way into the cadence. The last bar of a
  # phrase is its landing note and a breath.
  def self.right(seed, config, ladder, degrees, phrases, range)
    rng = rng(seed, 'right')
    motifs = Array.new(2) { motif(rng, config.fetch('motifs')) }
    lows = ladder.within(range)
    notes = []
    cursor = ladder.nearest(0, ladder.closest_to_midi(72, range), range)
    previous = nil
    phrases.each_with_index do |phrase, p|
      arrivals = arrivals(ladder, degrees, phrase, cursor, lows, range, rng)
      (phrase.first_bar...phrase.last_bar).each do |bar|
        2.times do |half|
          here = arrivals.fetch([bar, half])
          upcoming = half.zero? ? arrivals.fetch([bar, 1]) : arrivals.fetch([bar + 1, 0])
          landing = arrivals.fetch([phrase.last_bar, 0])
          figure = if half == 1 && bar == phrase.last_bar - 1 && ladder.chord_tone?(here, degrees[bar]) && (here - landing).abs == 1 then :trill
                   else choose(config, rng, here, upcoming, ladder, degrees[bar], previous)
                   end
          built = figure_notes(figure, here, upcoming, ladder, degrees[bar], rng, motifs, previous, lows)
          previous = [figure, built]
          built.inject((bar * BAR) + (half * 8)) do |at, (idx, len)|
            notes << Note.new(at, len, ladder.midi(idx.clamp(lows.min, lows.max)), (at % 4).zero? ? 1.0 : 0.8, p)
            at + len
          end
        end
      end
      landing = arrivals.fetch([phrase.last_bar, 0])
      notes << Note.new(phrase.last_bar * BAR, p == phrases.size - 1 ? BAR : 12, ladder.midi(landing), 1.0, p)
      cursor = landing
    end
    notes
  end

  # The chord tone to land on at the start of each half bar of a phrase, along an arch that peaks
  # about two thirds through; the last is the tonic for the closing cadences and a tone of the
  # chord for the half cadence.
  def self.arrivals(ladder, degrees, phrase, cursor, lows, range, rng)
    slots = (phrase.bars - 1) * 2
    peak = lows.min + 6 + rng.rand([lows.size - 7, 1].max)
    landing = phrase.cadence == 'half' ? ladder.nearest_tone(degrees[phrase.last_bar], cursor, range) : ladder.nearest(0, cursor, range)
    turn = (slots * 0.65).round
    out = {}
    slots.times do |s|
      bar = phrase.first_bar + (s / 2)
      target = s <= turn ? cursor + (((peak - cursor) * (s.to_f / [turn, 1].max)).round) : peak + (((landing - peak) * ((s - turn).to_f / [slots - turn, 1].max)).round)
      out[[bar, s % 2]] = ladder.nearest_tone(degrees[bar], target, range)
    end
    out[[phrase.last_bar, 0]] = landing
    out
  end

  def self.choose(config, rng, here, upcoming, ladder, degree, previous)
    table = config.fetch('figures').dup
    distance = (upcoming - here).abs
    table.delete('run8') if distance > 3
    table.delete('run16') if distance > 7
    table.delete('appoggiatura') if ladder.chord_tone?(here + 1, degree)
    table.delete('sequence') unless previous && previous.first == :motif
    table.delete(previous.first.to_s) if previous && previous.first != :motif && rng.rand < 0.6
    table.empty? ? :run8 : pick(table, rng).to_sym
  end

  # [index, length] pairs for one half bar, eight sixteenths in all.
  def self.figure_notes(figure, here, upcoming, ladder, degree, rng, motifs, previous, lows)
    side = (upcoming <=> here).nonzero? || 1
    case figure
    when :run16 then lens_path([1] * 8, here, upcoming, rng, lows)
    when :run8 then lens_path([2] * 4, here, upcoming, rng, lows)
    when :dotted then lens_path([3, 1, 3, 1], here, upcoming, rng, lows)
    when :neighbor then [[here, 2], [here + side, 2], [here, 2], [upcoming - side, 2]]
    when :turn then [[here + 1, 1], [here, 1], [here - 1, 1], [here, 1], [upcoming - side, 4]]
    when :appoggiatura then [[here + 1, 3], [here, 1]] + lens_path([2, 2], here, upcoming, rng, lows)
    when :held then [[here, 4]] + lens_path([2, 2], here, upcoming, rng, lows)
    when :motif then land_motif(motifs.sample(random: rng).map { |off, len| [here + off, len] }, upcoming)
    when :sequence
      shift = rng.rand < 0.5 ? 1 : -1
      land_motif(previous.last.map { |idx, len| [idx + shift, len] }, upcoming)
    when :trill then [[here, 1], [here + 1, 1], [here, 1], [here + 1, 1], [here, 1], [here + 1, 1], [here, 2]]
    else raise ArgumentError, "no figure #{figure.inspect} for degree #{degree}"
    end
  end

  # Unit steps from `start` to a note beside `goal`, in as many notes as `lens` has. A run shorter
  # than the way is a run; a longer one wanders by neighbour notes first.
  def self.lens_path(lens, start, goal, rng, lows)
    moves = lens.size - 1
    reach = ->(e) { (e - start).abs <= moves && (moves - (e - start).abs).even? && lows.include?(e) }
    finish = [goal - 1, goal + 1, goal].select(&reach).min_by { |e| [(e - goal).abs == 1 ? 0 : 1, (e - goal).abs, rng.rand] } || start
    direction = finish <=> start
    wander = (moves - (finish - start).abs) / 2
    steps = ([direction.zero? ? 1 : direction] * (finish - start).abs) + ([1, -1] * wander)
    steps = steps.shuffle(random: rng) unless wander.zero?
    idx = start
    path = [idx] + steps.map { |m| idx += m }
    path = path.map { |i| i.clamp(lows.min, lows.max) }
    path << path.last while path.size < lens.size
    path.first(lens.size).zip(lens)
  end

  # Draw a motif's last note to a step beside the next arrival, from the side it came.
  def self.land_motif(shape, upcoming)
    came = (shape[-2]&.first || shape.last.first) <=> upcoming
    shape[-1] = [upcoming + (came.zero? ? 1 : came), shape.last.last]
    shape
  end

  def self.motif(rng, spec)
    lens = spec.fetch('rhythms').sample(random: rng)
    offsets = lens.each_index.inject([0]) { |acc, _| acc + [acc.last + spec.fetch('steps').sample(random: rng)] }.first(lens.size)
    offsets.zip(lens)
  end

  # --------------------------------------------------------------------- checks
  # The piece answers for itself: every note in the scale and inside its line's range, the pedal
  # and the right hand never sounding two notes at once, no phrase outside two to four bars.
  def self.check(piece, ranges)
    piece.lines.each do |name, notes|
      range = ranges.fetch(name)
      notes.each do |n|
        raise "organ #{name}: #{n.midi} is outside the scale" unless piece.pcs.include?(n.midi % 12)
        raise "organ #{name}: #{n.midi} is outside #{range}" unless range.cover?(n.midi)
        raise "organ #{name}: a note of length #{n.length}" unless n.length.to_i.positive?
      end
      next if name == 'left'

      notes.sort_by(&:step).each_cons(2) { |a, b| raise "organ #{name}: a note at step #{a.step} runs into the next" if a.step + a.length > b.step }
    end
    raise 'organ: a phrase outside two to four bars' unless piece.phrases.all? { |ph| ph.bars.between?(2, 4) }
  end
end
