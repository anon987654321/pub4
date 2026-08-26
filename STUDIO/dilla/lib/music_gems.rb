# frozen_string_literal: true

require "timeout"

# Thin adapter over community Ruby music gems (GitHub-sourced).
#   coltrane  — pedrozath/coltrane — chord parsing, voicings, progression analysis
#   midilib   — jimm/midilib — Standard MIDI File I/O
#   wavefile  — jstrait/wavefile — WAV read without ffmpeg
#   head_music — roberthead/head_music — pitch-class / interval analysis
#
# Falls back to dilla.rb's inline theory when gems are unavailable.
module DillaMusicGems
  PAD_OCTAVE = 3
  PAD_VOICES = 5

  module_function

  # One rescue used to wrap every require, so a single missing gem set all four
  # flags to false and the only report was gated behind DILLA_DEBUG. That is how
  # a broken `require` survived: 797af1469's rename sweep matched the bare word
  # `coltrane` and rewrote the gem name — and the require of a gem that does not
  # exist reported nothing, disabled head_music/midilib/wavefile which had loaded
  # fine, and left chord parsing silently on the inline fallback for two days.
  #
  # A bundler/setup conflict genuinely does poison the whole set (see dilla.rb's
  # header on require ordering), so that one keeps the wide rescue. A missing
  # individual gem now costs only itself, and says so.
  def bootstrap!
    return @bootstrapped if defined?(@bootstrapped) && @bootstrapped

    @coltrane = @midilib = @wavefile = @head_music = false
    @bootstrapped = true

    gemfile = File.expand_path("../../../MASTER/Gemfile", __dir__)
    if File.file?(gemfile)
      ENV["BUNDLE_GEMFILE"] ||= gemfile
      begin
        require "bundler/setup"
      rescue LoadError, StandardError => e
        warn "dilla gems: bundler/setup failed (#{e.class}: #{e.message}) — " \
             "all four gems unavailable, falling back to inline theory"
        return @bootstrapped
      end
    end

    # head_music must load before coltrane — loading it after breaks ClassicScales on Ruby 4.
    @head_music = load_gem("head_music") { require "ostruct"; require "head_music" }
    @coltrane = load_gem("coltrane") do
      require "coltrane"
      require File.expand_path("../../../MASTER/lib/boot/hash_dig_compat", __dir__)
      Master.install_hash_dig_compat!
    end
    @midilib = load_gem("midilib") { require "midilib" }
    @wavefile = load_gem("wavefile") { require "wavefile" }
    @bootstrapped
  end

  # Names the gem and what is lost. Not gated on a debug flag: a missing gem
  # changes what the engine renders, so it is not debug output.
  def load_gem(name)
    yield
    true
  rescue LoadError => e
    warn "dilla gems: #{name} unavailable (#{e.message}) — falling back to inline theory for it"
    false
  end

  def available?
    bootstrap!
    @coltrane || @midilib || @wavefile || @head_music
  end

  def coltrane?
    bootstrap!
    @coltrane == true
  end

  def midilib?
    bootstrap!
    @midilib == true
  end

  def wavefile?
    bootstrap!
    @wavefile == true
  end

  def head_music?
    bootstrap!
    @head_music == true
  end

  # Map dilla/Jazz symbols → coltrane names (always use M for major).
  def coltrane_chord_name(sym)
    s = sym.to_s.strip
    return if s.empty?
    return if s.match?(/nc\z|fil\z|e_major_third_rise|over|add9|add11|Maj13|DMaj/i)
    # Qualities the gem either cannot name or names lossily. Everything listed
    # here falls through to producer_dna's suffix parser, which builds them
    # from CHORD_TEMPLATES.
    #
    # 7b9 and mMaj7 were added 2026-07-29: the gem answered both, so neither
    # reached the templates, and what it returned had the characteristic note
    # missing -- G7b9 came back as an unaltered G7 (no Ab at all) and CmMaj7
    # as a shape with neither the minor third nor the major seventh. A
    # dominant whose flat nine is gone is a dominant, which is the same
    # failure the sus and m7b5 entries above already document.
    return if s.match?(/7alt|7#11|7b9|m7b5|mmaj7|sus|aug|dim/i) && !s.match?(/\A[A-G][#b]?7sus4\z/i)

    s = s.sub(/maj9low\z/i, "M9").sub(/maj9\z/i, "M9").sub(/maj7\z/i, "M7")
         .sub(/maj6\z/i, "M6").sub(/maj\z/i, "M")
    unless s.match?(/M\d/)
      s = s.sub(/m11\z/, "m11").sub(/m9\z/, "m9").sub(/m7\z/, "m7").sub(/m\z/, "m")
    end
    s.match?(/\A[A-G][#b]?(M|m|\d)/) ? s : nil
  end

  def chord_from_symbol(sym, octave: PAD_OCTAVE, voices: PAD_VOICES)
    return unless coltrane?

    raw = sym.to_s.strip
    bass_note = nil
    if raw.include?("/") && !raw.include?("/9")
      upper, bass_note = raw.split("/", 2)
      raw = upper.strip
    end

    cname = coltrane_chord_name(raw)
    return unless cname

    chord = ::Coltrane::Chord.new(name: cname)
    low = raw.match?(/low\z/i)
    oct = low ? [octave - 1, 2].max : octave
    midis = chord.notes.map do |n|
      ::Coltrane::Pitch.new(note: n.name, octave: oct).midi
    end.sort.uniq
    while midis.length < voices
      midis << (midis.first + 12)
      midis.sort!
      midis.uniq!
    end
    hz = midis.last(voices).map do |m|
      ::Coltrane::Pitch[m].frequency.to_f.round(2)
    end
    if bass_note
      bass_hz = ::Coltrane::Pitch.new(note: bass_note.strip, octave: 2).frequency.to_f.round(2)
      hz[hz.index(hz.min)] = bass_hz
      hz.sort!
      return { name: sym.to_s, hz:, bass_hz: }
    end
    { name: sym.to_s, hz: }
  rescue ::Coltrane::ChordNotFoundError, StandardError
    nil
  end

  def progression_analysis(symbols)
    return unless coltrane?
    names = symbols.map { |s| coltrane_chord_name(s) }.compact
    return if names.length < 2

    # coltrane has hung indefinitely on specific chord symbols (Dm7b5, Cmaj9
    # — see README / producer_dna.rb#chord_from_symbol); bound it the same
    # way rather than let a render freeze forever with no exception raised.
    hits = Timeout.timeout(1.5) { ::Coltrane::Progression.find(*names) }
    return if hits.empty?

    best = hits.first
    {
      notation: best.notation,
      scale: best.scale&.name || best.scale&.to_s,
      notes_out: best.notes_out_size,
      chords: names,
    }
  rescue StandardError
    nil
  end

  def chord_candidates_from_pitch_classes(pitch_classes, limit: 16)
    return [] unless coltrane?

    pcs = pitch_classes.map { |pc| pc.to_i % 12 }.uniq.sort
    return [] if pcs.length < 3

    names = %w[C C# D D# E F F# G G# A A# B]
    roots = pcs.map { |pc| names[pc] }
    qualities = %w[M m M7 m7 M9 m9 7 9 6 m6 M6 dim dim7 aug sus4]
    hits = []
    roots.each do |root|
      qualities.each do |q|
        cname = "#{root}#{q}"
        begin
          # Same bounded-hang precaution as progression_analysis/chord_from_symbol:
          # any single Chord.new(name:) in this up-to-84-iteration sweep can hang.
          chord_pcs = Timeout.timeout(1.5) do
            ::Coltrane::Chord.new(name: cname).notes.map { |n| n.integer % 12 }.uniq.sort
          end
          overlap = (chord_pcs & pcs).length
          next if overlap < 3
          hits << { name: cname, overlap:, coverage: overlap.to_f / chord_pcs.length }
        rescue StandardError
          next
        end
      end
    end
    hits.sort_by { |h| [-h[:overlap], -h[:coverage]] }.first(limit)
  rescue StandardError
    []
  end

  def midi_ensure!
    bootstrap!
    return true if defined?(::MIDI::Sequence)
    raise LoadError, "midilib not installed — run: cd MASTER && bundle install" unless midilib?

    require "midilib"
    require "midilib/sequence"
    require "midilib/track"
    require "midilib/consts"
    true
  end

  # Mono float samples in [-1, 1]; nil → caller uses ffmpeg pipe.
  def read_mono_wav(path)
    return unless wavefile? && path.to_s.downcase.end_with?(".wav")
    return unless File.file?(path)

    samples = []
    ::WaveFile::Reader.new(path).each_buffer(4096) do |buffer|
      fmt = buffer.format
      ch = [fmt.channels, 1].max
      buffer.samples.each do |frame|
        val = frame.is_a?(Array) ? frame.first : frame
        samples << (val.to_f / (fmt.sample_format == :pcm_16 ? 32_768.0 : 1.0)).clamp(-1.0, 1.0)
      end
    end
    samples
  rescue StandardError
    nil
  end

  def pitch_class_set(pitch_classes)
    return unless head_music?

    pcs = pitch_classes.map { |pc| pc.to_i % 12 }
    ::HeadMusic::Analysis::PitchClassSet.new(pcs)
  rescue StandardError
    nil
  end

  def status
    bootstrap!
    {
      coltrane: coltrane?,
      midilib: midilib?,
      wavefile: wavefile?,
      head_music: head_music?,
    }
  end
end
