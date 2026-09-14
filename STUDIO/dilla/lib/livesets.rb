# frozen_string_literal: true

# The livesets: three sets patched into one room, and the journal that makes a
# pass something you can play again.
#
#   ruby dilla.rb live set chord_based_beats     one pass of a set
#   ruby dilla.rb live set sampled_based_beats
#   LIVE_VOICING=up ruby dilla.rb live set sampled_based_beats   the 08-31 voicings
#   ruby dilla.rb live set ambient_pads
#   ruby dilla.rb live recall                    the last twenty passes
#   ruby dilla.rb live recall 41205993           play that one again
#   ruby dilla.rb live recall 41205993 keep      render it beside dilla.rb
#   ruby dilla.rb live recall keep               keep the last pass played
#   ruby dilla.rb live broadcast [set]           all three in turn, or one all night
#   ruby dilla.rb live dig                       fill samples/chopped/ from project/crate.yml
#
# What the sets share is the room -- the console, the crate, the clock and the
# journal -- and what differs is the arrangement, which is what a set is. Written
# as three standalone scripts the console drifted between them, and the same beat
# sounded like three rooms.
#
# Sonitex STX-1260 and Nasty VCS, as chains rather than as plugins. Multiple
# instances deliberately: one instance is a colour and three are a sound. The
# 1260 is the 12-bit sampler lineage -- bit reduction, a hard band limit, drive
# into that limit. VCS is a summing colour, applied wherever things are added,
# which is what a console does and why summed material glues.
#
# The two bed sets play chops from samples/chopped/. With that rack empty they
# stop with "no beds" rather than playing silence; `dig` refills it.
require "fileutils"
require "json"
require "rbconfig"
require "shellwords"
require "time"
require "yaml"

module Livesets
  D = File.expand_path("..", __dir__)
  # Homebrew's build where it is installed, whatever PATH resolves otherwise.
  def self.tool(name)
    brew = "/opt/homebrew/bin/#{name}"
    File.executable?(brew) ? brew : name
  end
  FF = tool("ffmpeg")
  FFPLAY = tool("ffplay")
  FFPROBE = tool("ffprobe")
  JOURNAL = File.join(D, "project", "liveset.jsonl")
  WORTH = File.join(D, "project", "sample_worth.json")
  SETS = %w[chord_based_beats sampled_based_beats ambient_pads].freeze
  # Beats twice as often as pads: a pad block is 180 seconds against their 96, so
  # an even rotation would spend half the night on the quiet one.
  ROTATION = %w[sampled_based_beats chord_based_beats sampled_based_beats ambient_pads].freeze

  # The kit is one-shots or it is arithmetic. drunk_kit synthesises its four hits
  # from a sine and two noise bursts, which is a drum machine, not a record; the
  # lineage this room is after ran one-shots taken off real machines and run to
  # tape. A directory under samples/drums/ qualifies if it has all four roles.
  KIT_ROLES = %w[kick snare ghost hat].freeze

  NOTE_PC = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }.freeze
  # The tables were written by ear over years and spell chords the way a person
  # writing them down does: "C7#9 Hendrix" carries a note to the reader,
  # "Ebm7fil" a filter tag, "m9overC" a slash chord without the slash, and
  # "maj9nc"/"maj9low" a rendering instruction. None of it changes which notes
  # sound, so it comes off before the lookup. Measured over all 288 distinct
  # symbols in the tables: every one parses, and every quality resolves.
  ALIAS = { "m" => "min", "7sus" => "9sus", "7sus4" => "9sus4", "mMaj7" => "mmaj7" }.freeze

  module_function

  # A pass has to be nameable, or these are not sets.
  #
  # An Ableton set opens the same way every time; that is most of what a set is.
  # Everything that varies here -- which bed, how far it drags, which
  # progression, where the slice is taken, how drunk each hit is -- comes out of
  # one PRNG, so one number names the whole pass. LIVE_SEED replays it.
  #
  # The bed is pinned separately by LIVE_BED and not by the seed alone. pick_bed
  # reads the journal for recency, and the journal grows every pass, so the same
  # seed lands on a different record tomorrow.
  def seed!
    n = (ENV["LIVE_SEED"] || Random.new_seed % 2_147_483_647).to_i
    srand(n)
    n
  end

  def sonitex(bits:, lo:, hi:, drive:)
    "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1," \
      "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
  end

  # aphaser's delay floor is 0.1; under it nothing is audible and the knob only
  # appears to turn. aphaser is not unity either: in_gain and out_gain multiply,
  # so 0.6 x 0.72 is a 7dB cut per instance and three instances threw away 22dB
  # before the limiter saw the signal. Makeup here rather than at the master, so
  # each console stage stays level-neutral and the weights mean what they say.
  def vcs(depth:, smear:)
    "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
      "volume=1.9," \
      "aecho=0.9:0.25:#{smear.round}:0.08"
  end

  # Naming a kit that does not resolve aborts rather than falling back: silently
  # rendering the synthesised kit under a sampled kit's name puts a lie in the
  # journal, and the journal is what makes a pass recallable.
  def kit_dir
    want = ENV.fetch("LIVE_KIT", "").to_s
    return nil if want.empty? || want == "synth"

    dir = File.join(D, "samples", "drums", want)
    missing = KIT_ROLES.reject { |r| File.file?(File.join(dir, "#{r}.wav")) }
    abort "kit #{want}: no #{missing.join(', ')}" unless missing.empty?

    dir
  end

  # Every pass is written down before it is heard. The rig was ephemeral once and
  # a swept scratchpad took the takes with it -- provenance living somewhere more
  # fragile than what it describes. kit is merged rather than passed by each set:
  # a pass replayed with a different kit is a different take wearing the same
  # seed, so the name has to be in the line. drunk_kit sets it, so the pad set --
  # which has no drums -- records none.
  def journal!(row)
    row = { kit: @kit_used }.merge(row) if @kit_used
    File.open(JOURNAL, File::WRONLY | File::APPEND | File::CREAT, 0o644) do |fh|
      fh.flock(File::LOCK_EX)
      fh.write("#{JSON.generate(row)}\n")
      fh.flush
    end
  rescue StandardError
    nil # a journal that cannot write must not stop the music
  end

  def worth
    @worth ||= begin
      JSON.parse(File.read(WORTH))["slugs"]
    rescue StandardError
      {}
    end
  end

  # Least recently played, not random. Random repeats: with fifty racks it played
  # the same four beds inside ten minutes, which reads as a short loop rather than
  # as a crate. The journal already records what played and when, so it is also
  # the play history -- one file, two jobs, no second source to drift.
  def recency
    played = Hash.new(0)
    File.foreach(JOURNAL).with_index do |line, i|
      slug = line[/"bed":"([^"]+)"/, 1]
      played[slug] = i if slug # later line wins: this is recency, not a count
    end
    played
  rescue StandardError
    {}
  end

  # Beauty first, then recency. project/sample_worth.json ranks every rack by the
  # seven-term scorer -- tonal centre, overtone organisation, consonance below
  # 1kHz, voicing density, chord-register presence, whether the bed holds, and how
  # thin the arrangement is against the record's own habit. Verified independent
  # of level: Pearson(sw, rms_db) = 0.082 across 122 unique racks.
  #
  # The top half by beauty, then least-recently-played within it -- so the rig
  # works through the good regions rather than ranking once and repeating the
  # winner all night. Below eight racks the filter has nothing to choose from.
  def pick_bed
    beds = Dir.glob(File.join(D, "samples", "chopped", "*", "loop.wav"))
    abort "no beds" if beds.empty?
    slug_of = ->(b) { File.basename(File.dirname(b)) }
    if (want = ENV["LIVE_BED"].to_s) && !want.empty?
      pinned = beds.find { |b| slug_of.call(b) == want }
      abort "no such bed: #{want}" unless pinned

      return [pinned, want, worth.fetch(want, nil)]
    end
    ranked = beds.sort_by { |b| -worth.fetch(slug_of.call(b), 0.35).to_f }
    pool = ranked.size >= 8 ? ranked.first((ranked.size * 0.5).ceil) : ranked
    seen = recency
    # Its own generator, not the seeded stream. The tiebreak between two equally
    # stale beds is not part of what a seed names -- and if it drew from the main
    # stream, pinning the bed on replay would skip that draw and shift every
    # choice after it, so the same seed would come back at a different drag with
    # a different progression. Measured exactly that before it was separated.
    @tiebreak ||= Random.new
    bed = pool.min_by { |b| [seen.fetch(slug_of.call(b), -1), @tiebreak.rand] }
    [bed, slug_of.call(bed), worth.fetch(slug_of.call(bed), nil)]
  end

  # The grid comes from the record, not from a random number.
  #
  # chop cuts on bar lines, so a loop's duration is its tempo: one bar is the
  # whole loop divided by however many bars it holds. ffprobe measures the file
  # because it is the one reader that cannot go stale.
  #
  # And the drag moves the tempo with the pitch. asetrate slows the sample, so a
  # bar that was T seconds is now T/drag, and a kit built on the undragged figure
  # would run ahead of the record all night.
  def grid(bed, drag, want: 90, range: 76..104)
    raw = `#{FFPROBE} -v quiet -show_entries format=duration -of csv=p=0 #{bed.shellescape}`.to_f
    raw = 3.0 if raw <= 0.2
    # Whole bars only, and the reading that lands in a tempo a human would count.
    bars = [1, 2, 4, 8].min_by do |b|
      implied = (b * 4 * 60.0) / (raw / drag)
      range.cover?(implied) ? (implied - want).abs : 1_000 + (implied - want).abs
    end
    bar = ((raw / drag) / bars).round(4)
    beat = (bar / 4).round(4)
    { raw: raw, bars_in_loop: bars, bar: bar, beat: beat,
      step: (beat / 2).round(4), sxt: (beat / 4).round(4), bpm: (60.0 / beat).round(1) }
  end

  # One one-shot, split and dropped at each of its hit times. aevalsrc is avoided
  # on long durations -- ruinously slow -- so one-shots are synthesised once,
  # short, and placed with adelay, which costs nothing.
  def place(idx, label, filt, hits)
    out = ["[#{idx}:a]#{filt}[#{label}_s]"]
    out << "[#{label}_s]asplit=#{hits.size}#{(0...hits.size).map { |k| "[#{label}x#{k}]" }.join}"
    # adelay refuses a negative delay, and the jitter that makes the drums drunk
    # can push a hit on the one below zero. Clamped here rather than at every call
    # site, so the graph either builds or it does not.
    hits.each_with_index do |ms, k|
      d = [ms, 0].max.round
      out << "[#{label}x#{k}]adelay=#{d}|#{d}[#{label}p#{k}]"
    end
    out << "#{(0...hits.size).map { |k| "[#{label}p#{k}]" }.join}" \
           "amix=inputs=#{hits.size}:normalize=0[#{label}]"
    out
  end

  # Drunk drums. Dilla time is not a swing setting -- the kick and the snare drag
  # in different directions and by different amounts, and the hats do not agree
  # with either. Appends its own sources and returns the index of the last one,
  # which is the crackle. On the synthesised kit the hats and the record noise are
  # the same long pink generator read twice: 0.006 amplitude pink through a 7.2 kHz
  # high-pass is the hat, and the same noise unfiltered is the surface the whole
  # thing sits on, so they share a grain no two generators would.
  def drunk_kit(n, inputs, graph, beat:, bar:, step:, sxt:, total:)
    dir = kit_dir
    @kit_used = dir ? File.basename(dir) : "synth"
    # anoisesrc seeds itself from the clock unless told otherwise, so without
    # these a replayed seed comes back with every number identical and the audio
    # not. Derived from the pass seed so they follow it.
    s = ->(k) { "seed=#{(rand * 2_147_483_647).to_i + k}" }
    if dir
      KIT_ROLES.each { |r| inputs << "-i #{File.join(dir, "#{r}.wav").shellescape}" }
      inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.006:#{s.call(3)}"
    else
      inputs << "-f lavfi -t 0.32 -i sine=f=52:d=0.32"
      inputs << "-f lavfi -t 0.24 -i anoisesrc=c=pink:d=0.24:#{s.call(1)}"
      inputs << "-f lavfi -t 0.05 -i anoisesrc=c=white:d=0.05:#{s.call(2)}"
      inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.006:#{s.call(3)}"
    end

    jit = ->(ms) { (rand * ms * 2 - ms).round(1) }
    hits = {
      kick: [0.0, (bar / 2 + step)].map { |t| [(t * 1000).round + jit.call(9), 0].max },
      snare: [beat, beat * 3].map { |t| (t * 1000).round + 22 + jit.call(7) }, # behind the grid
      ghost: [(beat * 2 + sxt), (beat * 3 + sxt * 3)].map { |t| (t * 1000).round + jit.call(14) },
      hat: (0...8).map { |i| (i * step * 1000).round + (i.odd? ? 34 : 0) + jit.call(6) },
    }
    if dir
      # A synthesised hit needs a filter to become a drum and a recorded one
      # already is one, so a sampled kit gets almost nothing on the way in; the
      # shaping happens after the mix, in the 1260 and the console, which is where
      # it happened on the hardware too. The ghost is the snare played quiet and
      # short, because that is what a ghost note is.
      graph.concat place(n, "kk", "volume=1.5", hits[:kick])
      graph.concat place(n + 1, "sn", "volume=1.2", hits[:snare])
      graph.concat place(n + 2, "gh", "volume=0.42,afade=t=out:st=0.02:d=0.1", hits[:ghost])
      graph.concat place(n + 3, "hh", "volume=0.4", hits[:hat])
      graph << "[kk][sn][gh][hh]amix=inputs=4:weights=1.6 1.5 1 1:normalize=0,volume=1.3[kit_raw]"
    else
      graph.concat place(n, "kk", "volume=1.9,afade=t=out:st=0.015:d=0.24,lowpass=f=180," \
                                  "acrusher=bits=12:mode=log:aa=1", hits[:kick])
      graph.concat place(n + 1, "sn", "volume=1.5,afade=t=out:st=0.004:d=0.19," \
                                      "bandpass=f=1900:width_type=h:w=2600,volume=1.4", hits[:snare])
      graph.concat place(n + 2, "gh", "volume=0.24,afade=t=out:st=0.003:d=0.09," \
                                      "bandpass=f=2400:width_type=h:w=1800", hits[:ghost])
      graph.concat place(n + 3, "hh", "volume=0.26,afade=t=out:st=0.002:d=0.048,highpass=f=7200", hits[:hat])
      graph << "[kk][sn][gh][hh]amix=inputs=4:weights=2.8 2.4 1.1 1.0:normalize=0[kit_raw]"
    end
    graph << "[kit_raw]#{sonitex(bits: 11, lo: 42, hi: 12000, drive: 1.18)}," \
             "#{vcs(depth: 0.42, smear: 2.1)}[kit]"
    { hits: hits, crackle_i: n + 3 }
  end

  # Plays, unless LIVE_RENDER_TO names a file, in which case it writes one.
  # Keeping a pass and hearing it have to be the same code path or the take is
  # not the thing that was played.
  def play!(inputs, graph, banner)
    warn banner
    cmd = "#{FF} -nostdin -loglevel error #{inputs.join(' ')} " \
          "-filter_complex #{graph.join('; ').shellescape} -map \"[out]\""
    dest = ENV["LIVE_RENDER_TO"].to_s
    if dest.empty?
      exec("/bin/zsh", "-c",
           "#{cmd} -f wav - 2>/dev/null | #{FFPLAY} -nodisp -autoexit -loglevel quiet -i - 2>/dev/null")
    else
      FileUtils.mkdir_p(File.dirname(dest))
      ok = system("/bin/zsh", "-c", "#{cmd} -y #{dest.shellescape}")
      abort "render failed" unless ok

      warn "kept #{dest}"
    end
  end

  # chord_based_beats plays the builtin progressions.
  #
  # The other two sets are the crate: everything sounding in them is a record.
  # This one is the opposite and exists for the contrast. Nothing is sampled.
  # Every voice is a sine stacked into a chord the table names. The engine is
  # loaded for the tables rather than copied from, and for chord_from_root: copied,
  # the two would voice the same symbol differently within a month.

  def parse_chord(sym)
    s = sym.to_s.split(/\s+/).first.to_s
    bass = nil
    if (m = s.match(%r{(?:/|over)([A-G])([b#]?)\z}))
      bass = pc_of(m[1], m[2])
      s = s[0...m.begin(0)]
    end
    s = s.sub(/(?:fil|nc|low|climax)\z/, "").sub("s11", "#11")
    m = s.match(/\A([A-G])([b#]?)(.*)\z/) or return nil

    q = m[3].sub(/\AMaj/, "maj")
    q = "maj" if q.empty?
    [pc_of(m[1], m[2]), ALIAS.fetch(q, q), bass]
  end

  def pc_of(letter, acc) = (NOTE_PC.fetch(letter) + (acc == "b" ? -1 : acc == "#" ? 1 : 0)) % 12

  # The curated shortlist, not everything the engine can name. CHORD_PROGRESSIONS
  # includes DEVICE_PROGRESSIONS, which exist so a harmonic move can be reached
  # for by name and include the textbook furniture -- axis_major is C G Am F.
  # CURATED_PROGRESSIONS selects for progressions that loop cleanly, which is the
  # question a set asks, since a progression here is heard round and round for 96
  # seconds. ARTIST_VERIFIED_PROGRESSIONS joins it because a transcription from a
  # record is at least as trustworthy as a shortlist. Four or eight chords: two is
  # a vamp with no arc and sixteen outruns a 96-second block at this tempo.
  def chord_pool
    (CURATED_PROGRESSIONS + ARTIST_VERIFIED_PROGRESSIONS.keys).uniq
  end

  # The progression a pass plays, pinned by LIVE_PROGRESSION the way LIVE_BED
  # pins a bed. The pool is the catalogue's shortlist and the shortlist changes,
  # so a seed alone lands on a different progression once it has. The draw is
  # made either way, so pinning it leaves every later choice on the same stream.
  def pick_progression
    drawn = chord_pool.select { |k| v = CHORD_PROGRESSIONS[k]; v && [4, 8].include?(v.length) }.sample
    want = ENV["LIVE_PROGRESSION"].to_s
    return drawn if want.empty?

    abort "no such progression: #{want}" unless CHORD_PROGRESSIONS.key?(want.to_sym)

    want.to_sym
  end

  def chord_based_beats!
    total = 96
    seed = seed!
    # A2 to A3. There is no record to stay under, so the discipline is a low
    # register and a ceiling -- a synthesised chord voiced high is the one thing in
    # this room that would sound like a plugin.
    root_a = 110.0
    name = pick_progression
    symbols = CHORD_PROGRESSIONS.fetch(name)
    chords = symbols.filter_map { |s| [s, parse_chord(s)] if parse_chord(s) }

    # No record, so no record to take a tempo from. 82-94 is where the crate sits
    # once the drag is on it, and the kit is the same drunk kit, so the two beat
    # sets sit at the same count and can follow each other.
    bpm = (82 + rand * 12).round(1)
    beat = (60.0 / bpm).round(4)
    bar = (beat * 4).round(4)
    step = (beat / 2).round(4)
    sxt = (beat / 4).round(4)
    chord_s = (bar * (chords.size == 8 ? 0.5 : 1.0)).round(4)

    inputs = []
    graph = []

    chords.each_with_index do |(_sym, (pc, quality, bass)), i|
      root = root_a * (2**(pc / 12.0))
      # dilla's own voicing, so a symbol sounds here as it sounds in a render.
      hz = chord_from_root(root, quality, voices: 4)
      # A slash bass is the point of a slash chord: the note under everything,
      # an octave below the voicing rather than inside it.
      hz = [(root_a / 2) * (2**(bass / 12.0))] + hz if bass
      hz.each_with_index do |f, v|
        # Detuned by a few cents, alternating side. Four exact sines beat against
        # nothing and read as a test tone; a couple of cents apart they read as an
        # instrument, which is the cheapest honest way to get there.
        cents = v.zero? ? 0 : ((v.odd? ? 1 : -1) * (3 + v))
        f2 = (f * (2**(cents / 1200.0))).round(3)
        inputs << "-f lavfi -t #{(chord_s + 0.6).round(4)} -i sine=f=#{f2}:d=#{(chord_s + 0.6).round(4)}"
        idx = inputs.size - 1
        # Struck, not held: a fast front and a decay across the chord's length is
        # what makes this a beat set rather than the pad set with a synth in it.
        graph << "[#{idx}:a]atrim=0:#{chord_s},volume=#{(0.5 / (v + 1.4)).round(3)}," \
                 "afade=t=in:st=0:d=0.012," \
                 "afade=t=out:st=#{(chord_s * 0.22).round(3)}:d=#{(chord_s * 0.78).round(3)}[n#{i}v#{v}]"
      end
      graph << "#{(0...hz.size).map { |v| "[n#{i}v#{v}]" }.join}" \
               "amix=inputs=#{hz.size}:normalize=0," \
               "lowpass=f=2600,highpass=f=70[chd#{i}]"
    end

    graph << "#{chords.each_index.map { |i| "[chd#{i}]" }.join}concat=n=#{chords.size}:v=0:a=1," \
             "#{sonitex(bits: 12, lo: 70, hi: 7600, drive: 1.22)}," \
             "#{vcs(depth: 0.5, smear: 1.6)}," \
             "chorus=0.6:0.9:48|72:0.4|0.3:0.22|0.3:1.8|2.6," \
             "aecho=0.8:0.85:97|181:0.30|0.18," \
             "tremolo=f=#{(1.0 / bar).round(3)}:d=0.12," \
             "extrastereo=m=1.5[phrase]"

    kit = drunk_kit(inputs.size, inputs, graph, beat: beat, bar: bar, step: step, sxt: sxt, total: total)
    hits = kit[:hits]
    crackle_i = kit[:crackle_i]

    phrase_s = (chord_s * chords.size).round(4)
    graph << "[phrase][kit]amix=inputs=2:weights=0.62 2.9:normalize=0:duration=first," \
             "#{vcs(depth: 0.38, smear: 1.7)}," \
             "#{sonitex(bits: 12, lo: 40, hi: 13000, drive: 1.12)}," \
             "atrim=0:#{phrase_s},asetpts=N/SR/TB[barmix]"

    # The same arrangement rule as the sampled set: the harmony steps back in the
    # middle so the kit carries it, then returns. Measured in phrases here rather
    # than bars, because a phrase is four or eight chords and the drop has to land
    # on one of them.
    drop_from = (phrase_s * 2).round(3)
    drop_to = (phrase_s * 3).round(3)
    graph << "[barmix]aloop=loop=-1:size=#{(phrase_s * 44100).round},atrim=0:#{total}," \
             "volume='if(between(t,#{drop_from},#{drop_to}),0.5,1.0)':eval=frame," \
             "vibrato=f=1.5:d=0.11," \
             "acompressor=threshold=0.4:ratio=3.2:attack=9:release=210[body]"
    graph << "[#{crackle_i}:a]highpass=f=2200,volume=0.9," \
             "#{vcs(depth: 0.6, smear: 0.9)}[crackle]"
    graph << "[body][crackle]amix=inputs=2:weights=1 0.30:normalize=0:duration=first," \
             "#{vcs(depth: 0.34, smear: 2.4)}," \
             "#{sonitex(bits: 10, lo: 46, hi: 11500, drive: 1.1)}," \
             "#{vcs(depth: 0.26, smear: 3.6)}," \
             "aecho=0.85:0.7:83|151|229:0.20|0.12|0.06," \
             "treble=g=3:f=6500,bass=g=4:f=95," \
             "dynaudnorm=f=200:g=9:p=0.94:m=18," \
             "volume=2.4," \
             "alimiter=limit=0.98:level=disabled," \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      at: Time.now.utc.iso8601, seed: seed, set: "chord_based_beats", bed: nil, progression_name: name.to_s,
      progression: symbols, bpm: bpm, bar_s: bar, chord_s: chord_s,
      weights: { phrase: 0.62, kit: 2.9, crackle: 0.30 },
      drums: { kick_ms: hits[:kick], snare_ms: hits[:snare], ghost_ms: hits[:ghost], hat_ms: hits[:hat] },
      sonitex: [12, 12, 11, 10], vcs: 6, rig: "dilla.rb live set chord_based_beats"
    )

    play!(inputs, graph,
          "▶ chords  #{name}  #{bpm}bpm  #{chords.size} chords @ #{chord_s}s  " \
          "#{symbols.join(' ')}")
  end

  # sampled_based_beats plays the loop as an instrument.
  #
  # "Make old things sound new, and new things sound old." Old to new: a slice of
  # a 1970s bed is retriggered as chords the record never played -- asetrate is
  # sampler pitching, speed and pitch together, which is what an MPC does and why
  # chopped soul sounds like that. New to old: our own kit and the master go
  # through the 1260 and the console, so nothing arrives clean. Everything
  # sounding is the record except the kit and the crackle.

  # Voicings, not scale runs. Each step is a chord built from one slice: root, a
  # colour tone and an extension, so the sample states harmony it never had.
  # Downward only. Pitching a sample UP thins it and speeds it -- the chipmunk
  # sound -- and nothing in this lineage does it. Every interval here is zero or
  # negative, and the drag sits under all of it.
  SAMPLED_VOICINGS = {
    min7:  [0, -9, -2],    # root, b3 an octave down, b7 a tone below the root
    maj9:  [0, -8, -10],   # root, 3rd down an octave, 9th further under
    min9:  [0, -9, -10],
    sus4:  [0, -7, -2],
    min11: [0, -9, -7],
  }.freeze
  # Movement with rests in it. nil is a rest, and the rests are what make the rest
  # of it read as playing. Roots move down too, or the phrase climbs out of the
  # register the drag put it in.
  SAMPLED_PROGRESSIONS = [
    [[0, :min7], nil, [-5, :min9], [-3, :maj9], nil, [-2, :sus4], [0, :min7], nil],
    [[0, :min9], [-3, :min7], nil, [-7, :sus4], [-5, :maj9], nil, [-3, :min7], [0, :min11]],
    [[-7, :min7], nil, [-5, :min9], nil, [-3, :maj9], [0, :min7], nil, [-4, :sus4]],
    [[0, :min11], [0, :min11], nil, [-2, :maj9], [-3, :min7], nil, [-5, :min9], nil],
  ].freeze

  # LIVE_VOICING=up: the tables the rig played on 08-31, when the operator said
  # "i like it" of these passes. Built upward from the slice, so a chord climbs
  # above the record's pitch, and no clamp holds it under the drag. The downward
  # tables above stay the default; up is the operator's to reach for.
  UP_VOICINGS = {
    min7:  [0, 3, 10],
    maj9:  [0, 4, 14],
    min9:  [0, 3, 14],
    sus4:  [0, 5, 10],
    min11: [0, 3, 17],
  }.freeze
  UP_PROGRESSIONS = [
    [[0, :min7], nil, [5, :min9], [3, :maj9], nil, [-2, :sus4], [0, :min7], nil],
    [[0, :min9], [3, :min7], nil, [7, :sus4], [5, :maj9], nil, [3, :min7], [0, :min11]],
    [[7, :min7], nil, [5, :min9], nil, [3, :maj9], [0, :min7], nil, [-4, :sus4]],
    [[0, :min11], [0, :min11], nil, [-2, :maj9], [3, :min7], nil, [5, :min9], nil],
  ].freeze
  VOICING_TABLES = {
    "down" => [SAMPLED_VOICINGS, SAMPLED_PROGRESSIONS],
    "up" => [UP_VOICINGS, UP_PROGRESSIONS],
  }.freeze

  # A voicing that does not resolve aborts, for the reason kit_dir gives: a pass
  # journalled under a voicing it did not play cannot be recalled.
  def voicing
    want = ENV.fetch("LIVE_VOICING", "down")
    abort "no voicing #{want.inspect} — have #{VOICING_TABLES.keys.join(', ')}" unless VOICING_TABLES.key?(want)

    want
  end

  # Sampler ratios for one cell. Downward, every ratio is held at or under the
  # drag, so no arithmetic can pitch the record up; up leaves them where they fall.
  def slice_ratios(semi, intervals, drag, choice)
    intervals.map do |iv|
      ratio = (2.0**((semi + iv) / 12.0)) * drag
      (choice == "up" ? ratio : [ratio, drag].min).round(6)
    end
  end

  def sampled_based_beats!
    total = 96
    seed = seed!
    bed, slug, sw = pick_bed
    # 0.92-0.96: a semitone and a half down at the deep end, a third of one at the
    # shallow. Never none.
    drag = (0.92 + rand * 0.04).round(4)
    g = grid(bed, drag)
    bar = g[:bar]
    step = g[:step]
    choice = voicing
    voicings, progressions = VOICING_TABLES.fetch(choice)
    prog = progressions.sample
    slice_at = (rand * 2.2).round(3)
    reverse = rand < 0.28 # a reversed chop, sometimes

    inputs = []
    graph = []
    live = []

    prog.each_with_index do |cell, i|
      next if cell.nil?

      semi, quality = cell
      ratios = slice_ratios(semi, voicings.fetch(quality), drag, choice)
      longest = (step * ratios.max * 1.8).round(4)
      inputs << "-ss #{slice_at} -t #{longest} -i #{bed.shellescape}"
      idx = inputs.size - 1
      graph << "[#{idx}:a]asplit=3[c#{i}a][c#{i}b][c#{i}c]"
      %w[a b c].each_with_index do |tag, v|
        rev = reverse && v.zero? ? "areverse," : ""
        graph << "[c#{i}#{tag}]asetrate=44100*#{ratios[v]},aresample=44100,#{rev}" \
                 "atrim=0:#{step},volume=#{v.zero? ? 1.0 : 0.62}," \
                 "afade=t=in:st=0:d=0.005,afade=t=out:st=#{(step - 0.03).round(4)}:d=0.03[v#{i}#{tag}]"
      end
      graph << "[v#{i}a][v#{i}b][v#{i}c]amix=inputs=3:normalize=0[ch#{i}]"
      live << i
    end

    # Rests are silence of exactly one step, so the phrase keeps the grid.
    prog.each_index do |i|
      next if live.include?(i)

      inputs << "-f lavfi -t #{step} -i anullsrc=r=44100:cl=stereo"
      graph << "[#{inputs.size - 1}:a]atrim=0:#{step}[ch#{i}]"
    end
    graph << "#{prog.each_index.map { |i| "[ch#{i}]" }.join}concat=n=#{prog.size}:v=0:a=1," \
             "#{sonitex(bits: 12, lo: 90, hi: 9200, drive: 1.3)}," \
             "#{vcs(depth: 0.5, smear: 1.4)}," \
             "chorus=0.6:0.9:55:0.4:0.25:2," \
             "flanger=delay=4:depth=3:regen=22:speed=0.4," \
             "aecho=0.8:0.85:57|113:0.28|0.16," \
             "extrastereo=m=1.6[phrase]"

    kit = drunk_kit(inputs.size, inputs, graph, beat: g[:beat], bar: bar, step: step, sxt: g[:sxt], total: total)
    hits = kit[:hits]
    crackle_i = kit[:crackle_i]

    inputs << "-stream_loop -1 -i #{bed.shellescape}"
    bed_i = inputs.size - 1
    graph << "[#{bed_i}:a]asetrate=44100*#{drag},aresample=44100," \
             "atrim=0:#{(bar * g[:bars_in_loop]).round(4)}," \
             "volume=0.42,lowpass=f=5200,aecho=0.8:0.7:60:0.3," \
             "#{sonitex(bits: 13, lo: 60, hi: 7200, drive: 1.1)}," \
             "#{vcs(depth: 0.55, smear: 1.1)}[under]"

    graph << "[phrase][under][kit]amix=inputs=3:weights=0.30 0.14 3.4:" \
             "normalize=0:duration=longest," \
             "#{vcs(depth: 0.38, smear: 1.7)}," \
             "#{sonitex(bits: 12, lo: 40, hi: 13000, drive: 1.12)}," \
             "atrim=0:#{bar},asetpts=N/SR/TB[barmix]"

    # Arrangement, not a loop on repeat: the phrase steps back for eight bars in the
    # middle so the kit and the record carry it, then returns. A beat that never
    # changes is a beat nobody listens to twice.
    drop_from = (bar * 16).round(3)
    drop_to = (bar * 24).round(3)
    graph << "[barmix]aloop=loop=-1:size=#{(bar * 44100).round},atrim=0:#{total}," \
             "volume='if(between(t,#{drop_from},#{drop_to}),0.55,1.0)':eval=frame," \
             "vibrato=f=1.7:d=0.14," \
             "acompressor=threshold=0.4:ratio=3.2:attack=9:release=210[body]"
    graph << "[#{crackle_i}:a]highpass=f=2200,volume=0.9," \
             "#{vcs(depth: 0.6, smear: 0.9)}[crackle]"
    graph << "[body][crackle]amix=inputs=2:weights=1 0.34:normalize=0:duration=first," \
             "#{vcs(depth: 0.34, smear: 2.4)}," \
             "#{sonitex(bits: 10, lo: 46, hi: 11500, drive: 1.1)}," \
             "#{vcs(depth: 0.26, smear: 3.6)}," \
             "aecho=0.85:0.7:83|151|229:0.20|0.12|0.06," \
             "tremolo=f=#{(2.0 / bar).round(3)}:d=0.10," \
             "treble=g=3:f=6500,bass=g=4:f=95," \
             "dynaudnorm=f=200:g=9:p=0.94:m=18," \
             "volume=2.4," \
             "alimiter=limit=0.98:level=disabled," \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      at: Time.now.utc.iso8601, seed: seed, set: "sampled_based_beats", bed: slug, sample_worth: sw,
      bpm: g[:bpm], drag: drag, bars_in_loop: g[:bars_in_loop], voicing: choice, progression: prog,
      chop_at: slice_at, reversed: reverse, bar_s: bar,
      weights: { phrase: 0.30, under: 0.14, kit: 3.4 },
      drums: { kick_ms: hits[:kick], snare_ms: hits[:snare], ghost_ms: hits[:ghost], hat_ms: hits[:hat] },
      sonitex: [13, 12, 12, 11, 10], vcs: 6, rig: "dilla.rb live set sampled_based_beats"
    )

    play!(inputs, graph,
          "▶ sampled  #{slug}  sw=#{format('%.2f', sw.to_f)}  #{g[:bpm]}bpm " \
          "(#{g[:bars_in_loop]}bar loop, drag #{drag})  " \
          "#{prog.map { |c| c ? "#{c[0]}#{c[1]}" : '.' }.join(' ')}" \
          "#{reverse ? '  REV' : ''}  chop@#{slice_at}s")
  end

  # ambient_pads holds the same crate instead of striking it.
  #
  # A chop is a short thing by construction -- best_trim hunts a two-to-fourteen
  # second repeat, and the beat sets play it in eighth-note stabs. Held for two
  # bars at a time the same slice stops being a stab and becomes a pad. Nothing is
  # synthesised: every sustained voice is the record, slowed, stacked under itself
  # and given time. No kit -- a pad set with drums in it is a beat with the drums
  # turned down, and the point of this set is the absence.

  # Wider than the beat sets' voicings and further down. A pad held for two bars
  # needs the octave underneath it or the stack beats against itself. Every
  # interval is zero or negative: nothing plays above the record's own pitch.
  PAD_VOICINGS = {
    min9:  [0, -12, -9, -22],
    maj9:  [0, -12, -8, -22],
    sus4:  [0, -12, -7, -19],
    min11: [0, -12, -9, -17],
  }.freeze
  # Four chords, eight bars, and the arc lands back where it started. A pad
  # progression that resolves somewhere else asks to be followed; this one does
  # not ask anything.
  PAD_PROGRESSIONS = [
    [[0, :min9], [-5, :maj9], [-3, :sus4], [0, :min11]],
    [[0, :sus4], [-2, :min9], [-7, :maj9], [-5, :min9]],
    [[-3, :maj9], [-5, :min11], [0, :min9], [-2, :sus4]],
  ].freeze

  def ambient_pads!
    total = 180
    seed = seed!
    # Deeper than the beat sets. Their 0.92-0.96 keeps a bed danceable; a pad is
    # allowed to sit a whole tone under the record, and the slower it runs the
    # more of the tail you hear, which is the material this set is made of.
    drag = (0.86 + rand * 0.05).round(4)
    bed, slug, sw = pick_bed
    # Two bars per chord, so the grid wants a slower count than the beat sets.
    g = grid(bed, drag, want: 70, range: 60..84)
    bar = g[:bar]
    hold = (bar * 2).round(4)
    prog = PAD_PROGRESSIONS.sample
    slice_at = (rand * 1.6).round(3)

    inputs = []
    graph = []

    prog.each_with_index do |(semi, voicing), i|
      ratios = PAD_VOICINGS.fetch(voicing).map { |iv| [((2.0**((semi + iv) / 12.0)) * drag), drag].min.round(6) }
      ratios.each_with_index do |r, v|
        # asetrate divides the duration by the ratio, so the slice taken has to be
        # `hold * r` long to come back out as `hold`. Half a second of margin: a
        # slice that runs out mid-pad gates, and a gate is the one thing a pad
        # cannot survive.
        inputs << "-ss #{slice_at} -t #{(hold * r + 0.5).round(4)} -i #{bed.shellescape}"
        idx = inputs.size - 1
        # Long in, longer out, and they overlap between chords -- the fade tail of
        # one is still sounding when the next arrives, so four slices read as one
        # moving surface rather than four events.
        graph << "[#{idx}:a]asetrate=44100*#{r},aresample=44100,atrim=0:#{hold}," \
                 "volume=#{v.zero? ? 0.9 : (0.62 - (v * 0.11)).round(2)}," \
                 "afade=t=in:st=0:d=#{(hold * 0.35).round(3)}," \
                 "afade=t=out:st=#{(hold * 0.45).round(3)}:d=#{(hold * 0.55).round(3)}[p#{i}v#{v}]"
      end
      graph << "#{(0...ratios.size).map { |v| "[p#{i}v#{v}]" }.join}" \
               "amix=inputs=#{ratios.size}:normalize=0[pad#{i}]"
    end

    # Gentler than the beat sets: 13 bits and a 6 kHz ceiling, because the crush
    # that reads as grit on a stab reads as hiss on something held.
    graph << "#{prog.each_index.map { |i| "[pad#{i}]" }.join}concat=n=#{prog.size}:v=0:a=1," \
             "#{sonitex(bits: 13, lo: 55, hi: 6200, drive: 1.05)}," \
             "#{vcs(depth: 0.55, smear: 2.8)}," \
             "chorus=0.7:0.9:70|95:0.45|0.3:0.2|0.28:1.6|2.4," \
             "aecho=0.9:0.85:180|340|610:0.42|0.28|0.17," \
             "extrastereo=m=1.9[phrase]"

    inputs << "-stream_loop -1 -i #{bed.shellescape}"
    bed_i = inputs.size - 1
    # The record itself, far down and far back: a bed to notice the absence of,
    # which is what keeps the pads from sounding synthesised.
    graph << "[#{bed_i}:a]asetrate=44100*#{(drag * 0.5).round(6)},aresample=44100," \
             "atrim=0:#{(hold * prog.size).round(4)},volume=0.18," \
             "lowpass=f=1800,aecho=0.9:0.8:420:0.4," \
             "#{sonitex(bits: 12, lo: 40, hi: 2600, drive: 1.0)}," \
             "#{vcs(depth: 0.6, smear: 3.2)}[under]"

    # Seeded, for the reason drunk_kit gives: unseeded noise makes a replayed pass
    # identical in every number and different in the audio.
    inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.010:seed=#{(rand * 2_147_483_647).to_i}"
    air_i = inputs.size - 1
    graph << "[#{air_i}:a]lowpass=f=4200,volume=0.7,#{vcs(depth: 0.5, smear: 4.0)}[air]"

    phrase_s = (hold * prog.size).round(4)
    graph << "[phrase][under]amix=inputs=2:weights=1.0 0.5:normalize=0:duration=first," \
             "atrim=0:#{phrase_s},asetpts=N/SR/TB[cycle]"
    # Split and concatenated, not aloop'd. A pad cycle is 1.5 million samples,
    # and at that size aloop stops being reproducible: the same seed and a
    # byte-identical filtergraph rendered two takes that differed at -17 dBFS RMS
    # against a -18.7 dB signal. Bisected to this filter and to nothing else in the
    # graph. Copying the cycle the number of times the block needs is exact.
    cycles = (total / phrase_s).ceil
    graph << "[cycle]asplit=#{cycles}#{(0...cycles).map { |k| "[cy#{k}]" }.join}"
    # One slow breath across the whole block rather than a tremolo rate:
    # 1/(phrase*2) puts the swell either side of the loop point, so the place the
    # cycle restarts is the place it is quietest.
    graph << "#{(0...cycles).map { |k| "[cy#{k}]" }.join}concat=n=#{cycles}:v=0:a=1,atrim=0:#{total}," \
             "volume='0.72+0.28*sin(2*PI*t/#{(phrase_s * 2).round(3)})':eval=frame," \
             "vibrato=f=0.28:d=0.06," \
             "acompressor=threshold=0.5:ratio=2.4:attack=180:release=900[body]"
    graph << "[body][air]amix=inputs=2:weights=1 0.30:normalize=0:duration=first," \
             "#{vcs(depth: 0.3, smear: 4.4)}," \
             "#{sonitex(bits: 12, lo: 42, hi: 9000, drive: 1.04)}," \
             "aecho=0.88:0.75:730|1130:0.24|0.14," \
             "treble=g=-2:f=7000,bass=g=3:f=110," \
             "dynaudnorm=f=400:g=13:p=0.9:m=10," \
             "volume=1.9," \
             "alimiter=limit=0.97:level=disabled," \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      at: Time.now.utc.iso8601, seed: seed, set: "ambient_pads", bed: slug, sample_worth: sw,
      bpm: g[:bpm], drag: drag, bars_in_loop: g[:bars_in_loop], progression: prog,
      chop_at: slice_at, hold_s: hold, bar_s: bar, drums: nil,
      weights: { phrase: 1.0, under: 0.5, air: 0.30 },
      sonitex: [13, 12, 12], vcs: 5, rig: "dilla.rb live set ambient_pads"
    )

    play!(inputs, graph,
          "▶ pads  #{slug}  sw=#{format('%.2f', sw.to_f)}  #{g[:bpm]}bpm " \
          "(#{g[:bars_in_loop]}bar loop, drag #{drag})  hold #{hold}s  " \
          "#{prog.map { |semi, v| "#{semi}#{v}" }.join(' ')}  chop@#{slice_at}s")
  end

  def play_set!(name)
    abort "no set #{name.inspect} — have #{SETS.join(', ')}" unless SETS.include?(name.to_s)

    send(:"#{name}!")
  end

  # Every pass the journal holds, torn rows named rather than dropped. The journal
  # is append-only from a live set, so a kill mid-write leaves exactly one
  # unparseable line -- and a replay that quietly drops it reports no passes for a
  # pass that happened.
  def passes
    return [] unless File.file?(JOURNAL)

    File.readlines(JOURNAL).filter_map.with_index(1) do |line, number|
      row = begin
        JSON.parse(line)
      rescue JSON::ParserError
        warn "recall: #{File.basename(JOURNAL)}:#{number} is not JSON — skipped"
        next
      end
      row if row["seed"] && row["set"]
    end
  end

  def show(rows)
    if rows.empty?
      puts "no seeded passes yet -- a set names itself when it plays"
      return
    end
    rows.last(20).each do |r|
      puts format("  %-10s %-20s %-28s %6s bpm  %s", r["seed"], r["set"],
                  r["bed"] || r["progression_name"] || "-", r["bpm"], r["at"])
    end
    puts "\n  ruby dilla.rb live recall <seed>          play it again"
    puts "  ruby dilla.rb live recall <seed> keep     render it beside dilla.rb"
  end

  # Play a pass again, or keep one. keep with no seed means the last pass
  # played, which is the way it is wanted: something goes past, it was good, and
  # reaching for the number is one step too many at that moment.
  #
  # A kept take is <set>_<seed>.wav beside dilla.rb, with the journal line beside
  # it as <set>_<seed>.json. The wav is gitignored like every render; the json is
  # not, so the take survives this machine even when the audio does not, and the
  # seed rebuilds it.
  def recall!(argv)
    # Words, not flags: dilla.rb reads every --flag as a render knob before a
    # command sees it, so a recall option spelled as one would never arrive.
    if argv.include?("help")
      puts File.read(__FILE__).lines.grep(/\A#   ruby dilla\.rb live recall/).map { |l| l.sub(/\A# /, "") }
      return
    end
    keep = argv.delete("keep")
    unknown = argv.reject { |a| a.match?(/\A\d+\z/) }
    abort("recall: unknown word #{unknown.join(' ')} -- see ruby dilla.rb live recall help") if unknown.any?
    seed = argv.shift
    rows = passes
    return show(rows) if seed.nil? && !keep

    row = seed ? rows.reverse.find { |r| r["seed"].to_s == seed.to_s } : rows.last
    abort(seed ? "no pass with seed #{seed}" : "nothing in the journal yet") unless row

    env = { "LIVE_SEED" => row["seed"].to_s }
    env["LIVE_BED"] = row["bed"].to_s if row["bed"]
    # The kit is part of the take, not part of the environment. Replaying a sampled
    # pass under whatever LIVE_KIT happens to be exported would come back with
    # different drums and the same seed printed over them.
    env["LIVE_KIT"] = row["kit"].to_s if row["kit"]
    env["LIVE_PROGRESSION"] = row["progression_name"].to_s if row["progression_name"]
    env["LIVE_VOICING"] = row["voicing"].to_s if row["voicing"]
    label = "#{row['set']} #{row['seed']}"
    if keep
      take = File.join(D, "#{row['set']}_#{row['seed']}")
      env["LIVE_RENDER_TO"] = "#{take}.wav"
      # The journal line is the sidecar. It already holds every decision the pass
      # made, so writing a second description of it would be a second source.
      File.write("#{take}.json", JSON.pretty_generate(row))
      warn "keeping #{label} -> #{File.basename(take)}.wav (the wav is gitignored; the .json is the tracked record)"
    else
      warn "replaying #{label}"
    end
    exec(env, RbConfig.ruby, File.join(D, "dilla.rb"), "live", "set", row["set"].to_s)
  end

  # Pass after pass until interrupted. A pass that exits non-zero moves on to the
  # next set rather than ending the night. Hard cuts between sets: a set that
  # crossfades into the next is catalogue item 11, a set of its own. A misspelt
  # set would otherwise fail every 0.2 seconds all night, so it is refused first.
  def broadcast!(name = nil)
    abort "broadcast: no set named #{name} -- have #{SETS.join(', ')}" if name && !SETS.include?(name)

    sets = name ? [name] : ROTATION
    sets.cycle do |set|
      system(RbConfig.ruby, File.join(D, "dilla.rb"), "live", "set", set)
      sleep 0.2
    end
  end

  # The crate, dug from its manifest — off YouTube, and therefore not cleared.
  #
  # Say that first, because lib/sampling.rb takes the opposite position on the
  # same question: it is the engine's archive.org and ccMixter digger, filtered to
  # material that clears, and fills samples/dug/ with material that clears. This
  # fills samples/chopped/ with material that does not. Rights are carried, not
  # checked; treat everything this writes as unlicensed until somebody clears it
  # by hand.
  #
  # Resumable -- a slug whose chopped rack exists is skipped -- so it can be killed
  # and restarted without losing a track. The dug source is deleted after its
  # chop: full-length WAVs plus their demucs stems do not fit on this disk, and
  # chop demucses and strips drums and vocals, so every rack arrives drumless and
  # the kit is always ours.
  YTDLP = ENV.fetch("YTDLP") { tool("yt-dlp") }
  # Eight minutes. A thirty-eight-minute ambient set is 417MB of source and hours
  # of demucs for a loop nobody will chop; the crate is songs, not sets.
  MAX_SECONDS = 480

  def dig_beds!
    Dir.chdir(D)
    # On stderr, every run. A header only warns the reader who opens the file,
    # and the person about to fill a crate with unlicensed material is at a prompt.
    warn "dig: YouTube rips — unlicensed, not cleared for release. " \
         "lib/sampling.rb is the path that clears (Internet Archive, LibriVox, expired copyright)."
    crate = YAML.safe_load_file("project/crate.yml")["crate"].select { |e| e["available"] }
    slugify = ->(t) { t.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")[0, 44] }

    crate.each_with_index do |entry, i|
      slug = slugify.call(entry["title"])
      next if slug.empty?
      next if entry["duration_s"].to_i > MAX_SECONDS

      if Dir.glob("samples/chopped/#{slug}*").any?
        puts "[#{i + 1}/#{crate.size}] have #{slug}"
        next
      end

      src = "samples/dug/#{slug}.wav"
      unless File.file?(src)
        puts "[#{i + 1}/#{crate.size}] dig #{slug}"
        system(YTDLP, "-f", "bestaudio", "--extract-audio", "--audio-format", "wav",
               "-q", "--no-warnings", "-o", "samples/dug/#{slug}.%(ext)s",
               "https://youtu.be/#{entry['id']}")
      end
      next puts("  MISS #{slug}") unless File.file?(src)

      puts "  chop #{slug} (#{File.size(src) / 1024 / 1024}MB)"
      system(RbConfig.ruby, "dilla.rb", "chop", src, out: File::NULL, err: File::NULL)
      File.delete(src) if File.file?(src)
      puts "  done #{slug}  racks=#{Dir.glob('samples/chopped/*/').size}"
    end
    puts "dig complete: racks=#{Dir.glob('samples/chopped/*/').size}"
  end
end
