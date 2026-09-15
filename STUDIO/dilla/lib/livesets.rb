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
#   ruby dilla.rb live recall 41205993 keep      render it to demo.wav, record it beside dilla.rb
#   ruby dilla.rb live recall keep               keep the last pass played
#   ruby dilla.rb live broadcast [set]           all three in turn, or one all night
#   ruby dilla.rb live dig                       fill samples/chopped/ from project/crate.yml
#   ruby dilla.rb live ab <set> KNOB=value       three arms of one seed, level-matched, interleaved
#
#   LIVE_ROOM=warm|dry|blown|tape|master|summed  the console the set plays through
#   LIVE_LENGTH=30                               the block in seconds
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
    # The engine's own pin follows the pass: a device from dilla.rb that draws
    # through seed_for or noise_seed repeats with the pass that called it, rather
    # than growing a second seed beside LIVE_SEED.
    ENV["RENDER_SEED"] = n.to_s
    # DILLA_FROZEN has nothing to hold still here: it stops a render writing the
    # learned state, and a set learns nothing. What a set writes is the journal,
    # which is the catalogue's record, and LIVE_JOURNAL is how a run keeps out.
    @seed = n
  end

  # The draw order of the pass stream is an interface: every journalled seed
  # names the draws in the order they fall, so a decision added later draws
  # from its own stream, keyed by its tag and the pass seed, and leaves every
  # earlier take where it was.
  def stream(tag)
    Random.new((@seed.to_i * 1_000_003) + stable_hash(tag))
  end

  # acrusher mixes half dry unless told otherwise, and for a long time nothing
  # told it: every 1260 stage ran at mix=0.5 without anyone choosing that. It is
  # named now, and the warm room keeps it, because the weights were set by ear
  # against it. `samples` is the other half of a 12-bit sampler -- its rate, not
  # its depth -- and 1 is off; the blown room turns both.
  def sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
    "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
      "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
  end

  # Every vcs stage lands at VCS_DB, whatever its depth and smear, and the makeup
  # is worked out from them rather than typed. The stage used to carry
  # volume=1.9 and an aecho whose out_gain of 0.25 cut 12.7 dB, which left each
  # instance 5.5 to 9.9 dB down depending on its depth, not level-neutral as it
  # claimed. The weights were tuned by ear against that console, so the room
  # keeps its mean loss, -7.5 dB, as the declared level: the balance holds and a
  # changed depth no longer moves it. Measured on pink noise, aphaser at
  # in 0.75 x out 0.85 is -2.6 dB at decay 0.26 rising 10.9 dB per unit of
  # decay, and 0.14 dB quieter per millisecond of delay past 2.1; aecho at
  # 0.9:1 is -0.65 dB. aphaser's delay floor is 0.1; under it nothing is heard.
  VCS_DB = -7.5
  AECHO_DB = -0.65

  def vcs(depth:, smear:, db: VCS_DB)
    phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
    "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
      "aecho=0.9:1:#{smear.round}:0.08," \
      "volume=#{(db - phaser_db - AECHO_DB).round(2)}dB"
  end

  # The console as data, one row per place the sets sum. A room is what happens
  # to these rows; the arrangement never names a number of its own.
  #
  # Instances measured, not assumed (220 Hz at -12 dBFS, pink noise for level):
  # one vcs-and-1260 pair puts the 2nd harmonic at -74 dB and the 3rd at -84;
  # each further pair lifts the 2nd by 3 to 7 dB up to four pairs, where it
  # flattens at -58, while the 3rd holds near -80 until the fifth pair and then
  # climbs 15 dB by the sixth. More is warmer up to four and edgier after. The
  # longest series path here -- kit, sum, master -- is four vcs and three 1260s,
  # the warm side of that line, so the counts stay. Alone, a 1260 stage adds
  # almost no harmonic at all at this level (3rd at -80, no 2nd): it is a band
  # limit and a drive into a limiter, and the colour is the vcs.
  KIT_CONSOLE = [[:sonitex, { bits: 11, lo: 42, hi: 12_000, drive: 1.18 }], [:vcs, { depth: 0.42, smear: 2.1 }]].freeze
  SUM_CONSOLE = [[:vcs, { depth: 0.38, smear: 1.7 }], [:sonitex, { bits: 12, lo: 40, hi: 13_000, drive: 1.12 }]].freeze
  CRACKLE_CONSOLE = [[:vcs, { depth: 0.6, smear: 0.9 }]].freeze
  MASTER_CONSOLE = [[:vcs, { depth: 0.34, smear: 2.4 }], [:sonitex, { bits: 10, lo: 46, hi: 11_500, drive: 1.1 }],
                    [:vcs, { depth: 0.26, smear: 3.6 }]].freeze
  CONSOLE = {
    "chord_based_beats" => {
      phrase: [[:sonitex, { bits: 12, lo: 70, hi: 7600, drive: 1.22 }], [:vcs, { depth: 0.5, smear: 1.6 }]],
      kit: KIT_CONSOLE, sum: SUM_CONSOLE, crackle: CRACKLE_CONSOLE, master: MASTER_CONSOLE,
    },
    "sampled_based_beats" => {
      phrase: [[:sonitex, { bits: 12, lo: 90, hi: 9200, drive: 1.3 }], [:vcs, { depth: 0.5, smear: 1.4 }]],
      under: [[:sonitex, { bits: 13, lo: 60, hi: 7200, drive: 1.1 }], [:vcs, { depth: 0.55, smear: 1.1 }]],
      kit: KIT_CONSOLE, sum: SUM_CONSOLE, crackle: CRACKLE_CONSOLE, master: MASTER_CONSOLE,
    },
    # Gentler than the beat sets: 13 bits and a 6 kHz ceiling on the pads,
    # because the crush that reads as grit on a stab reads as hiss on something
    # held.
    "ambient_pads" => {
      phrase: [[:sonitex, { bits: 13, lo: 55, hi: 6200, drive: 1.05 }], [:vcs, { depth: 0.55, smear: 2.8 }]],
      under: [[:sonitex, { bits: 12, lo: 40, hi: 2600, drive: 1.0 }], [:vcs, { depth: 0.6, smear: 3.2 }]],
      air: [[:vcs, { depth: 0.5, smear: 4.0 }]],
      master: [[:vcs, { depth: 0.3, smear: 4.4 }], [:sonitex, { bits: 12, lo: 42, hi: 9000, drive: 1.04 }]],
    },
  }.freeze
  # The engine's DILLA_MIX_BUSES is not called here, and need not be: it groups
  # the stems of a note-plan render into drums, harmony, bass and texture so a
  # bus can be worked as one. These sets have no stems to group -- they are
  # built as buses from the first filter, phrase, under, kit, crackle and air,
  # summed at the rows above -- so the grouping exists and the console on it is
  # what a room chooses.
  #
  # Where a source enters, as against where sources meet.
  SOURCE_STAGES = %i[phrase under kit air].freeze

  # Which room, from LIVE_ROOM. A room changes the colour of every row and keeps
  # each row's declared level, so the balance the weights set holds. Dry, blown
  # and tape hold it within 2.5 dB; master and summed are level-dependent -- a
  # stack of 1260s adds noise to a quiet signal and console_stack was trimmed
  # against a hot mix -- and live ab trims them before anything is compared.
  #
  #   warm     the console as tuned: the default.
  #   dry      no console. Every stage keeps its level and loses its colour: the
  #            control that says whether the room is worth having.
  #   blown    the 1260s at full wet, at half the sample rate, driven a quarter
  #            harder. The other side of mix=0.5.
  #   tape     the engine's tape machine ahead of the console on every source.
  #   master   every instance in series on the master, none on the buses, which
  #            is where a plugin chain on a master bus sits.
  #   summed   the engine's measured summing units -- console_sum on the buses,
  #            console_stack on the master -- where vcs was.
  ROOMS = %w[warm dry blown tape master summed].freeze

  def room
    want = ENV.fetch("LIVE_ROOM", "warm")
    abort "no room #{want.inspect} — have #{ROOMS.join(', ')}" unless ROOMS.include?(want)

    want
  end

  def console(set, stage)
    rows = CONSOLE.fetch(set).fetch(stage)
    send(:"room_#{room}", set, stage, rows).join(",")
  end

  def unit(kind, params) = send(kind, **params)

  # The level a row keeps when its colour is taken away. A 1260 row has no gain
  # of its own; its band limits take 1.7 dB out of pink noise at any level from
  # -44 to -18 dB, so that is what it leaves behind.
  SONITEX_DB = -1.7

  # A dry 1260 row keeps its limiter as well as its level: the limiters are the
  # console's gain structure, and without them the kit's peaks alone set what
  # the normaliser does to everything else, so dry measured the loss of the
  # limit rather than of the colour.
  def level_of(kind) = kind == :vcs ? "volume=#{VCS_DB}dB" : "volume=#{SONITEX_DB}dB,alimiter=limit=0.99"

  def room_warm(_set, _stage, rows) = rows.map { |kind, params| unit(kind, params) }
  def room_dry(_set, _stage, rows) = rows.map { |kind, _| level_of(kind) }

  # Harder into the crusher and its limiter, and the quarter taken back after,
  # so the room is louder only where the limiter says so.
  BLOWN_DRIVE = 1.25

  def room_blown(_set, _stage, rows)
    rows.map do |kind, params|
      next unit(kind, params) unless kind == :sonitex

      blown = params.merge(mix: 1.0, samples: 2, drive: (params[:drive] * BLOWN_DRIVE).round(3))
      "#{unit(kind, blown)},volume=#{(-20 * Math.log10(BLOWN_DRIVE)).round(2)}dB"
    end
  end

  def room_tape(set, stage, rows)
    warm = room_warm(set, stage, rows)
    SOURCE_STAGES.include?(stage) ? [Outboard.tape_machine] + warm : warm
  end

  # The master's own rows keep their level; the instances added to reach the
  # set's count are level-neutral, since the buses already kept theirs.
  def room_master(set, stage, rows)
    return rows.map { |kind, _| level_of(kind) } unless stage == :master

    count = CONSOLE.fetch(set).values.sum(&:size)
    rows.cycle.first(count).each_with_index.map do |(kind, params), i|
      i < rows.size || kind != :vcs ? unit(kind, params) : vcs(**params, db: 0.0)
    end
  end

  # console_sum is -1.1 dB and console_stack at three is 0.0 dB on pink noise,
  # so each is trimmed to the level the vcs it replaces declares.
  def room_summed(_set, stage, rows)
    rows.map do |kind, params|
      next unit(kind, params) unless kind == :vcs

      stage == :master ? "#{Outboard.console_stack(instances: 3)},volume=#{VCS_DB}dB" : "#{Outboard.console_sum},volume=#{VCS_DB + 1.1}dB"
    end
  end

  # What the journal says about the room, counted from the table rather than
  # typed beside it.
  def console_record(set)
    rows = CONSOLE.fetch(set).values.flatten(1)
    { room: room, sonitex: rows.filter_map { |kind, p| p[:bits] if kind == :sonitex }, vcs: rows.count { |kind, _| kind == :vcs } }
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
    File.open(journal_path, File::WRONLY | File::APPEND | File::CREAT, 0o644) do |fh|
      fh.flock(File::LOCK_EX)
      fh.write("#{JSON.generate(row)}\n")
      fh.flush
    end
  rescue StandardError
    nil # a journal that cannot write must not stop the music
  end

  # LIVE_JOURNAL moves the journal and LIVE_BEDS_DIR the rack, for a run that
  # must not write the catalogue's history or that plays beds from elsewhere: an
  # A/B arm, a probe, a tree exported from another commit.
  def journal_path = ENV.fetch("LIVE_JOURNAL", JOURNAL)
  def beds_dir = ENV.fetch("LIVE_BEDS_DIR", File.join(D, "samples", "chopped"))

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
    File.foreach(journal_path).with_index do |line, i|
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
    beds = Dir.glob(File.join(beds_dir, "*", "loop.wav"))
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
    # A bed with no length cannot be looped: -stream_loop -1 over an empty file
    # never reaches its end, and the pass hangs with nothing written.
    abort "bed #{bed} has no audio ffprobe can measure" if raw <= 0.2
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
  def drunk_kit(n, inputs, graph, set:, beat:, bar:, step:, sxt:, total:)
    dir = kit_dir
    @kit_used = dir ? File.basename(dir) : "synth"
    # anoisesrc seeds itself from the clock unless told otherwise, so without
    # these a replayed seed comes back with every number identical and the audio
    # not. Derived from the pass seed so they follow it, and spelt `seed=` at
    # each source so the audit in graph_problems can see them.
    s = ->(k) { (rand * 2_147_483_647).to_i + k }
    if dir
      KIT_ROLES.each { |r| inputs << "-i #{File.join(dir, "#{r}.wav").shellescape}" }
      inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.006:seed=#{s.call(3)}"
    else
      inputs << "-f lavfi -t 0.32 -i sine=f=52:d=0.32"
      inputs << "-f lavfi -t 0.24 -i anoisesrc=c=pink:d=0.24:seed=#{s.call(1)}"
      inputs << "-f lavfi -t 0.05 -i anoisesrc=c=white:d=0.05:seed=#{s.call(2)}"
      inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.006:seed=#{s.call(3)}"
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
    graph << "[kit_raw]#{console(set, :kit)}[kit]"
    { hits: hits, crackle_i: n + 3 }
  end

  # A graph that builds is not a graph that sounds. Two defects in these sets
  # were empty filters -- a trailing comma left by a Ruby comment inside a line
  # continuation -- which ffmpeg reports only as `No such filter: ''`, after the
  # inputs are open. So the graph is read before ffmpeg sees it: every chain
  # names a filter at each comma, every link label is made once and used once,
  # [out] exists, every input is read, and no noise source draws from the clock.
  def graph_problems(inputs, graph)
    made = Hash.new(0)
    used = Hash.new(0)
    problems = graph.flat_map { |statement| statement_problems(statement, made, used) }
    problems + label_problems(inputs, made, used) + source_problems(inputs)
  end

  def statement_problems(statement, made, used)
    m = statement.match(/\A((?:\[[^\]]+\])*)(.*?)((?:\[[^\]]+\])*)\z/m)
    m[1].scan(/\[([^\]]+)\]/).flatten.each { |label| used[label] += 1 }
    m[3].scan(/\[([^\]]+)\]/).flatten.each { |label| made[label] += 1 }
    empty = filter_names(m[2]).count { |name| name.strip.empty? }
    empty.zero? ? [] : ["#{empty} empty filter(s) in #{statement[0, 60]}"]
  end

  # Commas inside quotes or parentheses belong to an argument, as in
  # volume='if(between(t,1,2),0.5,1.0)'.
  def filter_names(body)
    depth = 0
    quoted = false
    body.each_char.with_object([+""]) do |ch, parts|
      quoted = !quoted if ch == "'"
      depth += { "(" => 1, ")" => -1 }.fetch(ch, 0) unless quoted
      next parts << +"" if ch == "," && depth.zero? && !quoted

      parts.last << ch
    end
  end

  def label_problems(inputs, made, used)
    streams, links = used.keys.partition { |label| label.match?(/\A\d+:a\z/) }
    problems = made.select { |_, n| n > 1 }.keys.map { |l| "[#{l}] made #{made[l]} times" }
    problems += links.reject { |l| made.key?(l) }.map { |l| "[#{l}] used but never made" }
    problems += links.select { |l| used[l] > 1 }.map { |l| "[#{l}] used #{used[l]} times" }
    problems += (made.keys - links - ["out"]).map { |l| "[#{l}] made but never used" }
    problems << "no [out]" unless made.key?("out")
    read = streams.map(&:to_i)
    problems += read.select { |i| i >= inputs.size }.uniq.map { |i| "input #{i} does not exist" }
    problems + (0...inputs.size).reject { |i| read.include?(i) }.map { |i| "input #{i} never read" }
  end

  def source_problems(inputs)
    inputs.select { |i| i.include?("anoisesrc=") && !i.match?(/anoisesrc=\S*seed=\d/) }
          .map { |i| "unseeded noise: #{i}" }
  end

  # The engine's devices, reached from the room rather than rebuilt in it. Each
  # draws from its own stream, so the pass stream a journalled seed names is
  # untouched, and each is journalled and recalled at the value a take made
  # before it existed.
  #
  # Two are not reached, and the reason is the same one. LowPassGate and WavMap
  # are per-sample Ruby that read and write audio files, and a set is one ffmpeg
  # graph running in real time whose only file is demo.wav. The engine keeps
  # both on its note-plan renders (LPG=1, WAV_MAP=<image>), where the audio
  # already exists as a file to hand them.
  #
  # RINGTONE_LAYER and PAD_LAYERS are not reached either. RINGTONE_LAYER is copy
  # machine, LPG, wav_map and voice stack as one decision for a note-plan
  # render; here the devices it bundles are reached one at a time where each has
  # a bus to act on, so the bundle has nothing left to switch. PAD_LAYERS stacks
  # FluidSynth soundfonts over a note plan, and the sets' pads have no note plan
  # to stack over: they are the record, held.
  def knob_int(name, default, range)
    raw = ENV.fetch(name, default.to_s)
    value = Integer(raw, exception: false)
    abort "#{name}=#{raw} is not a whole number in #{range}" unless value && range.cover?(value)
    value
  end

  # COPY_MACHINE on the record under the pads: the bed played several times at
  # once at harmonic speeds, drifting apart in time, which is what a bed far
  # down and far back is for. Four copies by default on the pad set and none on
  # the beat sets, whose record is a groove the cloud would smear. Only the
  # speeds at or under one: a copy above the record's pitch is the record sped
  # up, which nothing in this room does.
  COPIES = { "ambient_pads" => 4 }.freeze

  def copies(set) = knob_int("LIVE_COPY_MACHINE", COPIES.fetch(set, 0), 0..8)

  def copy_machine(set, from, to, duration)
    n = copies(set)
    return ["[#{from}]anull[#{to}]"] if n < 2

    plan = CopyMachine.plan(copies: 32, family: :harmonic, seed: stream("copymachine").rand(2**31))
    down = plan.select { |c| c.ratio <= 1.0 }.first(n).each_with_index.map { |c, i| CopyMachine::Copy.new(**c.to_h, index: i) }
    CopyMachine.filter_complex(down, input: from, out: to, duration: duration).split(";")
  end

  # VOICE_STACK on every held slice: three voices each playing all of it, a few
  # cents apart on the power law, so a slice is a section rather than a copy.
  # The cents go downward for the same reason the copies do.
  def voice_stack_plan
    n = knob_int("LIVE_VOICE_STACK", 3, 1..7)
    VoiceStack.plan(voices: n, detune_mode: :power, drift: 9.0, seed: stream("voicestack").rand(2**31))
  end

  def slice_chain(ratio, hold, gain)
    "asetrate=44100*#{ratio},aresample=44100,atrim=0:#{hold},volume=#{gain.round(3)}," \
      "afade=t=in:st=0:d=#{(hold * 0.35).round(3)}," \
      "afade=t=out:st=#{(hold * 0.45).round(3)}:d=#{(hold * 0.55).round(3)}"
  end

  def stacked_slice(idx, ratio, hold, gain, label)
    voices = voice_stack_plan
    return ["[#{idx}:a]#{slice_chain(ratio, hold, gain)}[#{label}]"] if voices.size == 1

    graph = ["[#{idx}:a]asplit=#{voices.size}#{voices.map { |vc| "[#{label}s#{vc.index}]" }.join}"]
    voices.each do |vc|
      detuned = (ratio * (2.0**(-vc.cents.abs / 1200.0))).round(6)
      graph << "[#{label}s#{vc.index}]#{slice_chain(detuned, hold, gain * vc.gain)}[#{label}d#{vc.index}]"
    end
    graph << "#{voices.map { |vc| "[#{label}d#{vc.index}]" }.join}amix=inputs=#{voices.size}:normalize=0," \
             "volume=#{(1.0 / voices.size).round(4)}[#{label}]"
  end

  # HOCKET across the sampled phrase: the cells are dealt to voices on the
  # pendulum and each voice sits at its own place in the stereo field, so the
  # line is played by an ensemble that hands it along rather than by one hand.
  HOCKET_PANS = { 1 => [0.0], 2 => [-0.5, 0.5], 3 => [-0.55, 0.0, 0.55], 4 => [-0.6, -0.2, 0.2, 0.6] }.freeze

  def hocket_voices(prog)
    n = knob_int("LIVE_HOCKET", 3, 1..4)
    events = prog.each_index.filter_map { |i| [i.to_f, 1.0, { hz: [i] }, 1.0] if prog[i] }
    split = MidiDevices::Hocket.split(events, voices: n, mode: :pendulum, seed: stream("hocket").rand(2**31))
    split.each_with_index.with_object({}) { |(voice, v), map| voice.each { |event| map[event[2][:hz].first] = v } }
  end

  def hocket_pan(voice_of, cell)
    n = voice_of.values.max.to_i + 1
    HOCKET_PANS.fetch(n).fetch(voice_of.fetch(cell, 0))
  end

  def pan_filter(pan)
    return "" if pan.zero?

    ",pan=stereo|c0=#{(1.0 - [pan, 0].max).round(3)}*c0|c1=#{(1.0 + [pan, 0].min).round(3)}*c1"
  end

  # BUS_PATCH, asked for by name: LIVE_BUS_PATCH=phrase puts a whole random
  # patch on that bus -- one source per destination, depths biased low. Not a
  # default: its destinations centre a lowpass at 3 kHz, which on buses this room
  # already limits at 6 to 9 kHz takes off more top than it moves, and nobody has
  # heard what it does to a set. The command file is text in scratch.
  def bus_patch(bus, bpm, total)
    return "" unless ENV["LIVE_BUS_PATCH"].to_s == bus.to_s

    matrix, = DillaModulation::PatchBay.random(bpm: bpm.to_f, routes: 3, seed: stream("buspatch").rand(2**31))
    prefix = DillaModulation.prefix_for(matrix, path: File.join(SCRATCH_DIR, "live_buspatch_#{Process.pid}.cmds"), duration: total)
    return "" unless prefix

    "#{[prefix, *matrix.routes.map { |r| "#{matrix.instance_name(r)}=#{r.param}=#{matrix.initial(r)}" }].join(',')},"
  end

  # The arrangement: what each bus plays when, as gain points over the block.
  #
  # LIVE_FORM names a form from the engine's FORM_PRESETS, stretched across the
  # block by the engine's own fitted_form_section, and each bus follows the
  # engine layer it is in SECTION_LAYER_GAIN_ARRANGED -- where the part that
  # carries a section boundary leaves rather than ducks, because a timbre change
  # moved the engine's novelty detector 14 times as far as a 6 dB level change.
  # It is a choice, as SECTION_LAYERS=full is in a render: an arranged intro on
  # the chord set is crackle alone. Unset, each set keeps its own drop.
  BUS_LAYERS = {
    "chord_based_beats" => { phrase: :harm, kit: :drums },
    "sampled_based_beats" => { phrase: :chops, under: :sample, kit: :drums },
    "ambient_pads" => { phrase: :pad, under: :sample },
  }.freeze

  def form
    want = ENV.fetch("LIVE_FORM", "").to_s
    return nil if want.empty?

    abort "no form #{want} — have #{FORM_PRESETS.keys.join(', ')}" unless FORM_PRESETS.key?(want.to_sym)
    want
  end

  # How loud each bus meets the others, as data a pass can be nudged by:
  # LIVE_WEIGHTS=phrase=3.2,kit=2.9 overrides any of them, and the journal keeps
  # what played, so recall puts a take's own balance back.
  WEIGHTS = {
    # The chord set's phrase was 0.62, and measured with each bus muted in turn
    # its chords sat 27 dB under its kit (-38.7 LUFS against -11.2): sines are an
    # eighth of full scale out of ffmpeg, and a beat set whose chords cannot be
    # heard is a drum loop. At 6.0 they sit 8 dB under (-19.0), a beat with
    # harmony in it. The take kept at 0.62 replays at 0.62.
    "chord_based_beats" => { phrase: 6.0, kit: 2.9, crackle: 0.30 },
    "sampled_based_beats" => { phrase: 0.30, under: 0.14, kit: 3.4, crackle: 0.34 },
    "ambient_pads" => { phrase: 1.0, under: 0.5, air: 0.30 },
  }.freeze

  def weights(set)
    given = ENV.fetch("LIVE_WEIGHTS", "").split(",").to_h do |pair|
      bus, value = pair.split("=", 2)
      number = Float(value.to_s, exception: false)
      abort "LIVE_WEIGHTS: #{pair.inspect} is not bus=number" unless number && WEIGHTS.fetch(set).key?(bus.to_s.strip.to_sym)

      [bus.strip.to_sym, number]
    end
    WEIGHTS.fetch(set).merge(given)
  end

  def mix_weights(set, *buses) = buses.map { |bus| weights(set).fetch(bus) }.join(" ")

  # Mute groups, from LIVE_MUTE=kit,phrase: a bus in the list plays at zero for
  # the whole block. The graph keeps its shape and the pass stream its draws, so
  # a muted pass is the same pass with a part out, and DRUMS=0 -- the engine's
  # own switch for the kit -- mutes it here too.
  MUTABLE = %w[phrase under kit crackle air].freeze

  def muted
    groups = ENV.fetch("LIVE_MUTE", "").split(",").map(&:strip).reject(&:empty?)
    unknown = groups - MUTABLE
    abort "LIVE_MUTE: no group #{unknown.join(', ')} — have #{MUTABLE.join(', ')}" if unknown.any?

    groups << "kit" if ENV["DRUMS"] == "0"
    groups.uniq
  end

  def mute(bus) = muted.include?(bus.to_s) ? "volume=0," : ""

  def arrangement(set, bar, total, drop)
    shape = arranged(set, bar, total, drop)
    shape.to_h { |bus, points| [bus, muted.include?(bus.to_s) ? [[0, 0.0]] : points] }
  end

  def arranged(set, bar, total, drop)
    layers = BUS_LAYERS.fetch(set)
    return layers.keys.to_h { |bus| [bus, bus == :phrase ? drop : [[0, 1.0]]] } unless form

    map = FORM_PRESETS.fetch(form.to_sym).fetch(:map)
    n_bars = [(total / bar).floor, 1].max
    sections = (0...n_bars).map { |b| fitted_form_section(map, b, n_bars) }
    layers.to_h do |bus, layer|
      points = sections.each_with_index.map { |kind, b| [(b * bar).round(3), SECTION_LAYER_GAIN_ARRANGED.fetch(kind, {}).fetch(layer, 1.0)] }
      [bus, points.chunk_while { |a, b| a.last == b.last }.map(&:first)]
    end
  end

  # One bus as a block: its cycle, padded to exact length, copied for the whole
  # block, then shaped. Buses are repeated apart and summed after, so each can
  # follow its own part of the arrangement and each can cycle at its own length.
  def block!(graph, bus, cycle_s, total, points, bpm:)
    graph << "[#{bus}]apad=whole_dur=#{cycle_s},atrim=0:#{cycle_s},asetpts=N/SR/TB[#{bus}_cycle]"
    graph.concat repeat("#{bus}_cycle", cycle_s, total, "#{bus}_block")
    graph << "[#{bus}_block]#{bus_patch(bus, bpm, total)}#{DillaAutomation.volume_filter(points)}[#{bus}_arranged]"
  end

  # The kit repeats every bar. The chord set used to mix its one-bar kit into a
  # four-bar phrase with amix duration=first, which pads the shorter input with
  # silence, so its drums played the first bar of every four: rendered on
  # 2026-09-15, bars two to four read nothing above 1.5 kHz. LIVE_KIT_CYCLE=phrase
  # is that shape, and the take kept under it replays with it.
  KIT_CYCLES = %w[bar phrase].freeze

  def kit_cycle
    want = ENV.fetch("LIVE_KIT_CYCLE", "bar")
    abort "no kit cycle #{want.inspect} — have #{KIT_CYCLES.join(', ')}" unless KIT_CYCLES.include?(want)

    want
  end

  def kit_cycle_s(bar, phrase_s) = kit_cycle == "phrase" ? phrase_s : bar

  # A cycle played for the whole block: split and concatenated, never aloop'd.
  # At 1.5 million samples aloop stopped being reproducible -- the same seed and
  # a byte-identical graph rendered two pad takes that differed at -17 dBFS RMS
  # against a -18.7 dB signal, bisected to that filter alone -- and at 120 000 it
  # held. Where between the two it fails was never found, and the beat sets'
  # cycles sit inside that unknown, so every set copies its cycle instead, which
  # is exact at any size. asplit holds what concat has not reached yet: the block
  # in memory, 34 MB for 96 seconds.
  def repeat(from, cycle_s, total, to)
    cycles = [(total / cycle_s).ceil, 1].max
    copies = (0...cycles).map { |k| "[#{from}#{k}]" }.join
    ["[#{from}]asplit=#{cycles}#{copies}", "#{copies}concat=n=#{cycles}:v=0:a=1,atrim=0:#{total}[#{to}]"]
  end

  # The block's length in seconds. LIVE_LENGTH sets it: a probe of a few bars, a
  # thirty-second interlude, twenty minutes left running. Read from the
  # environment rather than drawn, so the pass stream does not move.
  def seconds(default)
    want = ENV.fetch("LIVE_LENGTH", "").to_s
    return default if want.empty?

    value = Float(want, exception: false)
    abort "LIVE_LENGTH=#{want} is not a number of seconds" unless value&.positive?
    value
  end

  # Plays, unless LIVE_RENDER_TO names a file, in which case it writes one.
  # Keeping a pass and hearing it have to be the same code path or the take is
  # not the thing that was played.
  def play!(inputs, graph, banner)
    problems = graph_problems(inputs, graph)
    abort "graph: #{problems.join('; ')}" if problems.any?

    warn banner
    cmd = "#{FF} -nostdin -loglevel error #{inputs.join(' ')} " \
          "-filter_complex #{graph.join('; ').shellescape} -map \"[out]\""
    dest = ENV["LIVE_RENDER_TO"].to_s
    if dest.empty?
      exec("/bin/zsh", "-c",
           "#{cmd} -f wav - 2>/dev/null | #{FFPLAY} -nodisp -autoexit -loglevel quiet -i - 2>/dev/null")
    else
      render_to!(cmd, dest)
    end
  end

  # Where a render may land. The operator's rule, 2026-09-15: the only audio
  # file dilla keeps is demo.wav beside dilla.rb, and a render overwrites it. So
  # LIVE_RENDER_TO names demo.wav or "-", a wav down stdout for whatever reads
  # it; any other file is refused before a sample is made. What makes a kept
  # take survive is its journal line, not its audio.
  DEMO = File.join(D, "demo.wav")

  # And a render only takes demo.wav's name once it has finished: ffmpeg writes
  # demo.partial.wav and the finished file is renamed onto it, so a failed pass
  # leaves the last good demo where it was, and its fragment goes with it.
  def render_to!(cmd, dest)
    return system("/bin/zsh", "-c", "#{cmd} -f wav -") || abort("render failed") if dest == "-"
    abort "#{dest}: a render writes demo.wav beside dilla.rb or a wav to stdout (-), and no other file" unless File.basename(dest) == "demo.wav"

    FileUtils.mkdir_p(File.dirname(dest))
    partial = dest.sub(/(\.\w+)?\z/, '.partial\1')
    ok = system("/bin/zsh", "-c", "#{cmd} -y #{partial.shellescape}")
    FileUtils.rm_f(partial) unless ok # scan: intentional — the fragment this call just wrote
    abort "render failed" unless ok

    File.rename(partial, dest)
    warn "kept #{dest}"
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

  # How far the record is dragged under its own pitch, pinned by LIVE_DRAG. The
  # draw is made either way, as with LIVE_PROGRESSION, so a pinned drag moves no
  # later choice. Downward only: a drag above 1.0 is the record sped up.
  def pinned_drag(drawn)
    want = ENV.fetch("LIVE_DRAG", "").to_s
    return drawn if want.empty?

    value = Float(want, exception: false)
    abort "LIVE_DRAG=#{want} is not a ratio between 0.5 and 1.0" unless value && value.between?(0.5, 1.0)
    value
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
    total = seconds(96)
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
             "#{console('chord_based_beats', :phrase)}," \
             "chorus=0.6:0.9:48|72:0.4|0.3:0.22|0.3:1.8|2.6," \
             "aecho=0.8:0.85:97|181:0.30|0.18," \
             "tremolo=f=#{(1.0 / bar).round(3)}:d=0.12," \
             "extrastereo=m=1.5[phrase]"

    kit = drunk_kit(inputs.size, inputs, graph, set: "chord_based_beats", beat: beat, bar: bar, step: step, sxt: sxt, total: total)
    hits = kit[:hits]
    crackle_i = kit[:crackle_i]

    phrase_s = (chord_s * chords.size).round(4)
    # The same arrangement rule as the sampled set: the harmony steps back in the
    # middle so the kit carries it, then returns. Measured in phrases here rather
    # than bars, because a phrase is four or eight chords and the drop has to land
    # on one of them.
    drop = [[0, 1.0], [(phrase_s * 2).round(3), 0.5], [(phrase_s * 3).round(3), 1.0]]
    shape = arrangement("chord_based_beats", bar, total, drop)
    block!(graph, "phrase", phrase_s, total, shape[:phrase], bpm: bpm)
    block!(graph, "kit", kit_cycle_s(bar, phrase_s), total, shape[:kit], bpm: bpm)
    graph << "[phrase_arranged][kit_arranged]amix=inputs=2:weights=#{mix_weights('chord_based_beats', :phrase, :kit)}:normalize=0:duration=first," \
             "#{console('chord_based_beats', :sum)}," \
             "vibrato=f=1.5:d=0.11," \
             "acompressor=threshold=0.4:ratio=3.2:attack=9:release=210[body]"
    graph << "[#{crackle_i}:a]highpass=f=2200,volume=0.9," \
             "#{mute(:crackle)}#{console('chord_based_beats', :crackle)}[crackle]"
    graph << "[body][crackle]amix=inputs=2:weights=1 #{weights('chord_based_beats').fetch(:crackle)}:normalize=0:duration=first," \
             "#{console('chord_based_beats', :master)}," \
             "aecho=0.85:0.7:83|151|229:0.20|0.12|0.06," \
             "treble=g=3:f=6500,bass=g=4:f=95," \
             "dynaudnorm=f=200:g=9:p=0.94:m=18," \
             "volume=2.4," \
             "alimiter=limit=0.98:level=disabled," \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      at: Time.now.utc.iso8601, seed: seed, set: "chord_based_beats", seconds: total, bed: nil, progression_name: name.to_s,
      progression: symbols, bpm: bpm, bar_s: bar, chord_s: chord_s, kit_cycle: kit_cycle, form: form,
      bus_patch: ENV['LIVE_BUS_PATCH'], muted: muted.join(","),
      weights: weights("chord_based_beats"),
      drums: { kick_ms: hits[:kick], snare_ms: hits[:snare], ghost_ms: hits[:ghost], hat_ms: hits[:hat] },
      **console_record("chord_based_beats"), rig: "dilla.rb live set chord_based_beats"
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
    total = seconds(96)
    seed = seed!
    bed, slug, sw = pick_bed
    # 0.92-0.96: a semitone and a half down at the deep end, a third of one at the
    # shallow. Never none.
    drag = pinned_drag((0.92 + rand * 0.04).round(4))
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

    voice_of = hocket_voices(prog)
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
      graph << "[v#{i}a][v#{i}b][v#{i}c]amix=inputs=3:normalize=0#{pan_filter(hocket_pan(voice_of, i))}[ch#{i}]"
      live << i
    end

    # Rests are silence of exactly one step, so the phrase keeps the grid.
    prog.each_index do |i|
      next if live.include?(i)

      inputs << "-f lavfi -t #{step} -i anullsrc=r=44100:cl=stereo"
      graph << "[#{inputs.size - 1}:a]atrim=0:#{step}[ch#{i}]"
    end
    graph << "#{prog.each_index.map { |i| "[ch#{i}]" }.join}concat=n=#{prog.size}:v=0:a=1," \
             "#{console('sampled_based_beats', :phrase)}," \
             "chorus=0.6:0.9:55:0.4:0.25:2," \
             "flanger=delay=4:depth=3:regen=22:speed=0.4," \
             "aecho=0.8:0.85:57|113:0.28|0.16," \
             "extrastereo=m=1.6[phrase]"

    kit = drunk_kit(inputs.size, inputs, graph, set: "sampled_based_beats", beat: g[:beat], bar: bar, step: step, sxt: g[:sxt], total: total)
    hits = kit[:hits]
    crackle_i = kit[:crackle_i]

    inputs << "-stream_loop -1 -i #{bed.shellescape}"
    bed_i = inputs.size - 1
    graph << "[#{bed_i}:a]asetrate=44100*#{drag},aresample=44100," \
             "atrim=0:#{(bar * g[:bars_in_loop]).round(4)}," \
             "volume=0.42,lowpass=f=5200,aecho=0.8:0.7:60:0.3," \
             "#{console('sampled_based_beats', :under)}[under]"

    # Arrangement, not a loop on repeat: the phrase steps back for eight bars in the
    # middle so the kit and the record carry it, then returns. A beat that never
    # changes is a beat nobody listens to twice.
    shape = arrangement("sampled_based_beats", bar, total, [[0, 1.0], [(bar * 16).round(3), 0.55], [(bar * 24).round(3), 1.0]])
    %w[phrase under kit].each { |bus| block!(graph, bus, bar, total, shape[bus.to_sym], bpm: g[:bpm]) }
    graph << "[phrase_arranged][under_arranged][kit_arranged]amix=inputs=3:weights=#{mix_weights('sampled_based_beats', :phrase, :under, :kit)}:" \
             "normalize=0:duration=first," \
             "#{console('sampled_based_beats', :sum)}," \
             "vibrato=f=1.7:d=0.14," \
             "acompressor=threshold=0.4:ratio=3.2:attack=9:release=210[body]"
    graph << "[#{crackle_i}:a]highpass=f=2200,volume=0.9," \
             "#{mute(:crackle)}#{console('sampled_based_beats', :crackle)}[crackle]"
    graph << "[body][crackle]amix=inputs=2:weights=1 #{weights('sampled_based_beats').fetch(:crackle)}:normalize=0:duration=first," \
             "#{console('sampled_based_beats', :master)}," \
             "aecho=0.85:0.7:83|151|229:0.20|0.12|0.06," \
             "tremolo=f=#{(2.0 / bar).round(3)}:d=0.10," \
             "treble=g=3:f=6500,bass=g=4:f=95," \
             "dynaudnorm=f=200:g=9:p=0.94:m=18," \
             "volume=2.4," \
             "alimiter=limit=0.98:level=disabled," \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      at: Time.now.utc.iso8601, seed: seed, set: "sampled_based_beats", seconds: total, bed: slug, sample_worth: sw,
      bpm: g[:bpm], drag: drag, bars_in_loop: g[:bars_in_loop], voicing: choice, progression: prog,
      chop_at: slice_at, reversed: reverse, bar_s: bar, form: form, hocket: voice_of.values.max.to_i + 1,
      bus_patch: ENV['LIVE_BUS_PATCH'], muted: muted.join(","),
      weights: weights("sampled_based_beats"),
      drums: { kick_ms: hits[:kick], snare_ms: hits[:snare], ghost_ms: hits[:ghost], hat_ms: hits[:hat] },
      **console_record("sampled_based_beats"), rig: "dilla.rb live set sampled_based_beats"
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
    total = seconds(180)
    seed = seed!
    # Deeper than the beat sets. Their 0.92-0.96 keeps a bed danceable; a pad is
    # allowed to sit a whole tone under the record, and the slower it runs the
    # more of the tail you hear, which is the material this set is made of.
    drag = pinned_drag((0.86 + rand * 0.05).round(4))
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
        graph.concat stacked_slice(idx, r, hold, v.zero? ? 0.9 : (0.62 - (v * 0.11)).round(2), "p#{i}v#{v}")
      end
      graph << "#{(0...ratios.size).map { |v| "[p#{i}v#{v}]" }.join}" \
               "amix=inputs=#{ratios.size}:normalize=0[pad#{i}]"
    end

    graph << "#{prog.each_index.map { |i| "[pad#{i}]" }.join}concat=n=#{prog.size}:v=0:a=1," \
             "#{console('ambient_pads', :phrase)}," \
             "chorus=0.7:0.9:70|95:0.45|0.3:0.2|0.28:1.6|2.4," \
             "aecho=0.9:0.85:180|340|610:0.42|0.28|0.17," \
             "extrastereo=m=1.9[phrase]"

    inputs << "-stream_loop -1 -i #{bed.shellescape}"
    bed_i = inputs.size - 1
    # The record itself, far down and far back: a bed to notice the absence of,
    # which is what keeps the pads from sounding synthesised.
    graph << "[#{bed_i}:a]asetrate=44100*#{(drag * 0.5).round(6)},aresample=44100," \
             "atrim=0:#{(hold * prog.size).round(4)}[under_raw]"
    graph.concat copy_machine("ambient_pads", "under_raw", "under_cloud", (hold * prog.size).round(4))
    graph << "[under_cloud]volume=0.18," \
             "lowpass=f=1800,aecho=0.9:0.8:420:0.4," \
             "#{console('ambient_pads', :under)}[under]"

    # Seeded, for the reason drunk_kit gives: unseeded noise makes a replayed pass
    # identical in every number and different in the audio.
    inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.010:seed=#{(rand * 2_147_483_647).to_i}"
    air_i = inputs.size - 1
    graph << "[#{air_i}:a]lowpass=f=4200,volume=0.7,#{mute(:air)}#{console('ambient_pads', :air)}[air]"

    phrase_s = (hold * prog.size).round(4)
    shape = arrangement("ambient_pads", bar, total, [[0, 1.0]])
    %w[phrase under].each { |bus| block!(graph, bus, phrase_s, total, shape[bus.to_sym], bpm: g[:bpm]) }
    # One slow breath across the whole block rather than a tremolo rate:
    # 1/(phrase*2) puts the swell either side of the loop point, so the place the
    # cycle restarts is the place it is quietest.
    graph << "[phrase_arranged][under_arranged]amix=inputs=2:weights=#{mix_weights('ambient_pads', :phrase, :under)}:normalize=0:duration=first," \
             "volume='0.72+0.28*sin(2*PI*t/#{(phrase_s * 2).round(3)})':eval=frame," \
             "vibrato=f=0.28:d=0.06," \
             "acompressor=threshold=0.5:ratio=2.4:attack=180:release=900[body]"
    graph << "[body][air]amix=inputs=2:weights=1 #{weights('ambient_pads').fetch(:air)}:normalize=0:duration=first," \
             "#{console('ambient_pads', :master)}," \
             "aecho=0.88:0.75:730|1130:0.24|0.14," \
             "treble=g=-2:f=7000,bass=g=3:f=110," \
             "dynaudnorm=f=400:g=13:p=0.9:m=10," \
             "volume=1.9," \
             "alimiter=limit=0.97:level=disabled," \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      at: Time.now.utc.iso8601, seed: seed, set: "ambient_pads", seconds: total, bed: slug, sample_worth: sw,
      bpm: g[:bpm], drag: drag, bars_in_loop: g[:bars_in_loop], progression: prog,
      chop_at: slice_at, hold_s: hold, bar_s: bar, drums: nil, form: form,
      copy_machine: copies('ambient_pads'), voice_stack: voice_stack_plan.size, bus_patch: ENV['LIVE_BUS_PATCH'], muted: muted.join(","),
      weights: weights("ambient_pads"),
      **console_record("ambient_pads"), rig: "dilla.rb live set ambient_pads"
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
    return [] unless File.file?(journal_path)

    File.readlines(journal_path).filter_map.with_index(1) do |line, number|
      row = begin
        JSON.parse(line)
      rescue JSON::ParserError
        warn "recall: #{File.basename(journal_path)}:#{number} is not JSON — skipped"
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
    puts "  ruby dilla.rb live recall <seed> keep     render it to demo.wav and keep its record"
  end

  # Every choice a pass journals, by the knob that makes it and the value a row
  # from before that choice existed was played with. A choice is part of the
  # take, not part of the environment: replaying a sampled pass under whatever
  # LIVE_KIT or LIVE_ROOM happens to be exported would come back different with
  # the same seed printed over it, so every one is set from the row, and nil
  # unsets it. Adding a choice means adding its row here with the value it had
  # before, which is how a default can move without moving a kept take.
  RECALLED = {
    "LIVE_BED" => ["bed", nil], "LIVE_KIT" => ["kit", nil], "LIVE_PROGRESSION" => ["progression_name", nil],
    "LIVE_VOICING" => ["voicing", "down"], "LIVE_LENGTH" => ["seconds", nil], "LIVE_ROOM" => ["room", "warm"],
    "LIVE_KIT_CYCLE" => ["kit_cycle", "phrase"], "LIVE_FORM" => ["form", nil], "LIVE_MUTE" => ["muted", nil], "LIVE_WEIGHTS" => ["weights", nil], "LIVE_DRAG" => ["drag", nil],
    "LIVE_COPY_MACHINE" => ["copy_machine", "0"], "LIVE_VOICE_STACK" => ["voice_stack", "1"], "LIVE_HOCKET" => ["hocket", "1"],
    "LIVE_BUS_PATCH" => ["bus_patch", nil],
  }.freeze

  def recall_env(row)
    pins = RECALLED.to_h { |knob, (key, legacy)| [knob, row.key?(key) ? knob_value(row[key]) : legacy] }
    { "LIVE_SEED" => row["seed"].to_s }.merge(pins)
  end

  # A journalled choice as the knob spells it: a hash of weights goes back as
  # phrase=0.62,kit=2.9.
  def knob_value(value) = value.is_a?(Hash) ? value.map { |k, v| "#{k}=#{v}" }.join(",") : value&.to_s

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

    env = recall_env(row)
    label = "#{row['set']} #{row['seed']}"
    if keep
      take = File.join(D, "#{row['set']}_#{row['seed']}")
      env["LIVE_RENDER_TO"] = DEMO
      # The journal line is the sidecar. It already holds every decision the pass
      # made, so writing a second description of it would be a second source.
      File.write("#{take}.json", JSON.pretty_generate(row))
      warn "keeping #{label} -> demo.wav, and #{File.basename(take)}.json as the tracked record that rebuilds it"
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

  # A/B by rendering, as a command rather than a habit.
  #
  #   ruby dilla.rb live ab chord_based_beats 16 LIVE_ROOM=dry        the knobs, changed
  #   ruby dilla.rb live ab ambient_pads 24 ref=HEAD seed=777 play     this tree against a commit
  #
  # Three arms of one seed: baseline, a control that is the baseline again, and
  # the changed arm, which differs in the stated knobs or runs this tree where
  # the other two run `ref`. The control is what turns "these differ by 0.4 dB"
  # into a finding or into render noise. Every arm is level-matched to the
  # baseline before a band is compared, because the louder arm wins every
  # informal comparison. `play` then plays baseline and changed in turn, every
  # four seconds at matched level, because the verdict is heard, not hashed.
  #
  # No arm is a file. The only audio dilla keeps is demo.wav, so each arm is
  # rendered down a pipe into the measurement, and the audition renders the two
  # arms again down two pipes into the speaker.
  AB_WINDOW = 4.0
  AB_BANDS = [[30, 120], [120, 300], [300, 800], [800, 2000], [2000, 5000], [5000, 12_000]].freeze

  def ab!(argv)
    set = argv.shift
    abort "usage: ruby dilla.rb live ab <#{SETS.join('|')}> [seconds] [seed=N] [ref=<commit>] [play] [KNOB=value ...]" unless SETS.include?(set)

    play = argv.delete("play")
    plan = ab_plan(set, argv)
    work = File.join(SCRATCH_DIR, "live_ab_#{set}_#{plan[:seed]}_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
    FileUtils.mkdir_p(work)
    measures = plan[:arms].to_h { |arm, spec| [arm, ab_measure_arm(arm, spec, plan, work)] }
    trims = ab_trims(measures)
    report = ab_report(measures, trims)
    File.write(File.join(work, "report.txt"), report)
    puts report
    ab_audition(plan, trims, work) if play
  end

  # The arms as data, so which environment each one runs is testable without a
  # render. A bed set pins its bed once for all three: pick_bed breaks ties with
  # a free generator, and two arms on two records measure the records.
  def ab_plan(set, argv)
    words, knobs = argv.partition { |a| !a.match?(/\A[A-Z][A-Z0-9_]*=/) }
    opts = words.grep(/=/).to_h { |w| w.split("=", 2) }
    seconds = Float(words.grep_v(/=/).first || 16)
    seed = (opts["seed"] || Random.new_seed % 2_147_483_647).to_i
    abort "ab: nothing differs -- name a KNOB=value or ref=<commit>" if knobs.empty? && !opts["ref"]

    base = { "LIVE_SEED" => seed.to_s, "LIVE_LENGTH" => seconds.to_s }
    base["LIVE_BED"] = ENV["LIVE_BED"] || pick_bed[1] unless set == "chord_based_beats"
    changed = base.merge(knobs.to_h { |k| k.split("=", 2) })
    { set: set, seconds: seconds, seed: seed, ref: opts["ref"],
      arms: { "baseline" => [opts["ref"], base], "control" => [opts["ref"], base], "changed" => [nil, changed] } }
  end

  # What a render needs from this process, and the pins that name the pass
  # being compared, and nothing else: no arm inherits a knob the operator
  # exported for some other reason.
  AB_CARRIED = %w[PATH HOME TMPDIR LANG SHELL USER DILLA_SCRATCH_DIR
                  LIVE_KIT LIVE_PROGRESSION LIVE_VOICING].freeze

  # One arm as a shell command that writes its wav to stdout, journalling into
  # scratch so the catalogue's history does not grow by three passes.
  def ab_arm_command(arm, (ref, env), plan, work)
    journal = File.join(work, "#{arm}.jsonl")
    FileUtils.cp(journal_path, journal) if File.file?(journal_path)
    carried = AB_CARRIED.to_h { |k| [k, ENV.fetch(k, nil)] }.compact
    full = carried.merge(env, "LIVE_RENDER_TO" => "-", "LIVE_JOURNAL" => journal, "LIVE_BEDS_DIR" => beds_dir)
    assignments = full.map { |k, v| "#{k}=#{v}".shellescape }.join(" ")
    "env -i #{assignments} #{RbConfig.ruby.shellescape} #{ab_entry(ref, work).shellescape} " \
      "live set #{plan[:set]} 2>>#{File.join(work, "#{arm}.log").shellescape}"
  end

  def ab_measure_arm(arm, spec, plan, work)
    warn "measuring #{arm}#{spec.first ? " at #{spec.first}" : ''}…"
    measure = "#{FF} -nostdin -hide_banner -nostats -i - -filter_complex #{ab_measure_graph.shellescape} " \
              "-map '[loud]' -f null -"
    out = `/bin/zsh -c #{"#{ab_arm_command(arm, spec, plan, work)} | #{measure} 2>&1".shellescape}`
    ab_parse(out) || abort("ab: #{arm} rendered nothing measurable -- see #{arm}.log in #{work}")
  end

  # Loudness and six bands in one pass over the pipe. The bands are cascaded
  # twice each, so a neighbouring band does not leak into the reading.
  def ab_measure_graph
    splits = (0...AB_BANDS.size).map { |i| "[b#{i}]" }.join
    bands = AB_BANDS.each_with_index.map do |(lo, hi), i|
      "[b#{i}]highpass=f=#{lo},highpass=f=#{lo},lowpass=f=#{hi},lowpass=f=#{hi},volumedetect,anullsink"
    end
    (["[0:a]asplit=#{AB_BANDS.size + 1}[m]#{splits}", "[m]ebur128=peak=true[loud]"] + bands).join(";")
  end

  # ffmpeg's report, read back. volumedetect instances are numbered in the order
  # the graph declares them, which is the order of AB_BANDS.
  def ab_parse(text)
    summary = text[(text.rindex("Summary:") || return)..]
    lufs = summary[/I:\s+(-?[\d.]+) LUFS/, 1] or return nil
    bands = text.scan(/Parsed_volumedetect_(\d+) @ \S+\] mean_volume: (-?[\d.]+) dB/)
                .sort_by { |n, _| n.to_i }.map { |_, db| db.to_f }
    bands.size == AB_BANDS.size ? { lufs: lufs.to_f, bands: bands } : nil
  end

  # dilla.rb as it was at `ref`, exported into scratch with the MASTER code it
  # loads at boot. The crate is linked in rather than copied: an old tree reads
  # samples/ where it always did.
  AB_EXPORT = %w[STUDIO/dilla MASTER/lib MASTER/Gemfile MASTER/Gemfile.lock].freeze

  def ab_entry(ref, work)
    return File.join(D, "dilla.rb") unless ref

    tree = File.join(work, "tree_#{ref.gsub(/[^\w.-]/, '_')}")
    unless File.directory?(tree)
      FileUtils.mkdir_p(tree)
      root = `git -C #{D.shellescape} rev-parse --show-toplevel`.strip
      ok = system("/bin/zsh", "-c", "git -C #{root.shellescape} archive #{ref.shellescape} #{AB_EXPORT.join(' ')} | tar -x -C #{tree.shellescape}")
      abort "ab: cannot export #{ref}" unless ok
      File.symlink(File.join(D, "samples"), File.join(tree, "STUDIO", "dilla", "samples")) if File.directory?(File.join(D, "samples"))
    end
    File.join(tree, "STUDIO", "dilla", "dilla.rb")
  end

  # Decibels to add to each arm so its integrated loudness is the baseline's.
  def ab_trims(measures)
    measures.transform_values { |m| (measures.fetch("baseline")[:lufs] - m[:lufs]).round(2) }
  end

  def ab_report(measures, trims)
    bands = measures.to_h { |arm, m| [arm, m[:bands].map { |db| db + trims.fetch(arm) }] }
    noise = ab_band_move(bands, "control")
    moved = ab_band_move(bands, "changed")
    lines = trims.map { |arm, db| format("%-9s trim %+6.2f dB  bands %s", arm, db, bands[arm].map { |b| format('%6.1f', b) }.join(' ')) }
    verdict = moved > [noise * 2, 0.3].max ? "real" : "inside the noise"
    lines << format("level-matched, the changed arm moves a band %.1f dB against %.1f dB between two baselines -- %s",
                    moved, noise, verdict)
    "#{lines.join("\n")}\n"
  end

  def ab_band_move(bands, arm) = bands.fetch(arm).zip(bands.fetch("baseline")).map { |a, b| (a - b).abs }.max

  # Baseline and changed in turn, each at its trim, straight to the speaker.
  def ab_audition(plan, trims, work)
    a, b = %w[baseline changed].map { |arm| ab_arm_command(arm, plan[:arms].fetch(arm), plan, work) }
    graph = ab_interleave_graph(trims, plan[:seconds]).join(";")
    warn "playing: A baseline, B changed, every #{AB_WINDOW}s, level-matched"
    system("/bin/zsh", "-c", "#{FF} -nostdin -loglevel error -i <(#{a}) -i <(#{b}) -filter_complex #{graph.shellescape} " \
                             "-map '[out]' -f wav - | #{FFPLAY} -nodisp -autoexit -loglevel quiet -i -")
  end

  def ab_interleave_graph(trims, seconds)
    starts = (0...(seconds / AB_WINDOW).ceil).map { |k| k * AB_WINDOW }
    turns = starts.each_index.group_by(&:even?)
    graph = [[true, 0], [false, 1]].filter_map do |even, input|
      next unless turns[even]

      "[#{input}:a]asplit=#{turns[even].size}#{turns[even].map { |k| "[s#{k}]" }.join}"
    end
    starts.each_with_index do |t, k|
      graph << "[s#{k}]atrim=#{t}:#{[t + AB_WINDOW, seconds].min},asetpts=PTS-STARTPTS," \
               "volume=#{trims.fetch(k.even? ? 'baseline' : 'changed')}dB," \
               "afade=t=in:d=0.01,afade=t=out:st=#{AB_WINDOW - 0.02}:d=0.02[w#{k}]"
    end
    graph << "#{starts.each_index.map { |k| "[w#{k}]" }.join}concat=n=#{starts.size}:v=0:a=1[out]"
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
