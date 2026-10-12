# ------------------------------------------------------------------- chords
# A chord name becomes notes here and nowhere else: the root or slash bass in the low octave,
# then the upper structure. Each upper note starts as near as it can be to the last chord, and
# a search over octave shifts then picks the voicing that moves least, keeps the top line
# smooth and leaves no neighbours closer than a whole tone. No chord tone is ever dropped
# for spacing; only the fifth, then the root when the bass plays it, give way to the voice cap.
module Chords
  NOTE_PC = { 'C' => 0, 'D' => 2, 'E' => 4, 'F' => 5, 'G' => 7, 'A' => 9, 'B' => 11 }.freeze
  ACCIDENTAL = { 'b' => -1, '#' => 1, '' => 0 }.freeze

  # "Dbmaj7#11" => root pitch class, tones in semitones above the root, slash bass or nil.
  def self.parse(name)
    m = name.to_s.sub('6/9', '69').match(%r{\A([A-G])([b#]?)([^/]*)(?:/([A-G])([b#]?))?\z}) or
      raise ArgumentError, "chord #{name.inspect}: no root"
    bass = m[4] && (NOTE_PC.fetch(m[4]) + ACCIDENTAL.fetch(m[5])) % 12
    { pc: (NOTE_PC.fetch(m[1]) + ACCIDENTAL.fetch(m[2])) % 12, tones: tones(m[3], name), bass: bass }
  end

  # Triads, sixths, sevenths, ninths, elevenths, thirteenths, add9/11/13, sus2/sus4 and
  # the alterations b5 #5 b9 #9 #11 b13. Anything left over is an error, named.
  def self.tones(quality, name)
    s = quality.delete('(),')
    third = 4
    fifth = 7
    seventh = sixth = nil
    extensions = []
    third = 3 if s.sub!(/\A(?:min|mi|-|m(?!aj))/, '')
    if s.sub!(/\Adim/, '')
      third = 3
      fifth = 6
      seventh = 9 if s.start_with?('7')
    end
    fifth = 8 if s.sub!(/\A(?:aug|\+)/, '')
    third = 2 if s.sub!(/sus2/, '')
    third = 5 if s.sub!(/sus4|sus/, '')
    level = 0
    if s.sub!(/\A(?:maj|M)(7|9|11|13)?/, '')
      level = Regexp.last_match(1).to_i
      seventh = 11 if level.positive?
    elsif (digits = s[/\A(?:7|9|11|13)/])
      level = digits.to_i
      seventh ||= 10
      s.sub!(/\A(?:7|9|11|13)/, '')
    elsif s.sub!(/\A69/, '')
      sixth = 9
      extensions << 14
    elsif s.sub!(/\A6/, '')
      sixth = 9
    end
    extensions << 14 if level >= 9
    extensions << 17 if level == 11
    extensions << 21 if level >= 13
    extensions << 14 if s.sub!(/add9/, '')
    extensions << 17 if s.sub!(/add11/, '')
    extensions << 21 if s.sub!(/add13/, '')
    sixth = 9 if s.sub!(/add6/, '')
    if s.sub!(/alt/, '')
      seventh ||= 10
      fifth = nil
      extensions = [13, 20]
    end
    while (alteration = s.slice!(/[b#](?:5|9|11|13)/))
      case alteration
      when 'b5' then fifth = 6
      when '#5' then fifth = 8
      when 'b9' then extensions = extensions.reject { |e| e == 14 } + [13]
      when '#9' then extensions = extensions.reject { |e| e == 14 } + [15]
      when '#11' then extensions = extensions.reject { |e| e == 17 } + [18]
      when 'b13' then extensions = extensions.reject { |e| e == 21 } + [20]
      end
    end
    raise ArgumentError, "chord #{name.inspect}: cannot read #{s.inspect}" unless s.empty?

    ([0, third, fifth, sixth, seventh] + extensions).compact.uniq.sort
  end

  MAX_VOICES = 5   # the bass and four above it
  LOW = 52         # the upper structure sits between these two notes
  HIGH = 84
  MIN_GAP = 2      # neighbours are at least a whole tone apart: no minor second rubs
  CENTRE = 66      # the middle of that register, which the search is gently pulled toward
  PULL = 0.1       # semitones of cost per semitone the voicing sits from the centre

  # The tones above the bass, as pitch classes. The root stays out when the bass already
  # plays it and the chord has more than a triad; when the chord is over the voice cap the
  # perfect fifth goes first, then an altered fifth, then the root. The third or sus tone,
  # the sixth or seventh and every named extension are never dropped.
  def self.upper_pcs(chord)
    bass_pc = chord[:bass] || chord[:pc]
    tones = chord[:tones].dup
    tones -= [0] if tones.size > 3 && bass_pc == chord[:pc]
    [[7], [6, 8], [0]].each do |drop|
      tones -= drop if tones.size > MAX_VOICES - 1
    end
    tones.map { |semi| (chord[:pc] + semi) % 12 }.uniq
  end

  # The note for a pitch class nearest any of the reference notes, inside the register.
  def self.nearest(pc, reference)
    options = (LOW..HIGH).select { |n| n % 12 == pc }
    options.min_by { |n| [reference.map { |r| (n - r).abs }.min, n] }
  end

  def self.valid?(upper)
    upper.first >= LOW && upper.last <= HIGH && upper.each_cons(2).all? { |a, b| b - a >= MIN_GAP }
  end

  # Mean distance each new note moves from its nearest old one, plus the top line's own
  # movement at full weight, plus a small pull toward the middle of the register.
  def self.cost(upper, before)
    pull = PULL * (upper.sum.to_f / upper.size - CENTRE).abs
    return pull if before.empty?

    mean = upper.sum { |n| before.map { |b| (n - b).abs }.min }.to_f / upper.size
    mean + (upper.last - before.last).abs + pull
  end

  # One voicing as MIDI notes, lowest first. Each upper note starts at the one nearest the
  # last chord, then the search tries every octave shift (down, none, up) on every voice and
  # keeps the cheapest set that has no duplicate pitch and no neighbours closer than MIN_GAP.
  def self.voice(name, previous = nil, search: true)
    chord = parse(name)
    bass = 36 + (((chord[:bass] || chord[:pc]) - 36) % 12)
    before = previous ? previous.drop(1) : []
    reference = before.empty? ? [CENTRE] : before
    start = upper_pcs(chord).map { |pc| nearest(pc, reference) }.sort
    return [bass] + apart(start) unless search

    best = nil
    [-12, 0, 12].repeated_permutation(start.size) do |shifts|
      upper = start.zip(shifts).map { |n, s| n + s }.sort
      next unless valid?(upper)

      score = cost(upper, before)
      best = [score, upper] if best.nil? || score < best.first - 1e-9
    end
    [bass] + (best ? best.last : apart(start))
  end

  # A minor second between neighbours is a rub: the upper one goes up an octave, or when
  # that leaves the register the lower one goes down.
  def self.apart(notes)
    out = notes.sort
    12.times do
      i = (1...out.size).find { |k| out[k] - out[k - 1] < MIN_GAP } or break
      out[i] + 12 <= HIGH ? out[i] += 12 : out[i - 1] -= 12
      out.sort!
    end
    out
  end

  def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

  # One voicing per chord of a progression, as MIDI notes; each leads from the one before.
  # `transpose` moves every note by that many semitones after voicing (no resampling, the
  # timing is untouched); `wrap` then folds any note still above the audible top down by octaves.
  def self.midi_notes(names, search: true, transpose: 0, wrap: false)
    previous = nil
    names.map do |name|
      previous = voice(name, previous, search:)
      notes = previous.map { |n| n + transpose }
      wrap ? notes.map { |n| fold(n) } : notes
    end
  end

  def self.fold(note)
    note -= 12 while hz(note) > AUDIBLE_TOP_HZ
    note
  end

  def self.freqs(names, search: true, transpose: 0, wrap: false)
    midi_notes(names, search:, transpose:, wrap:).map { |notes| notes.map { |n| hz(n) } }
  end
end

