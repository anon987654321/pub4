# frozen_string_literal: true

# The livesets: three sets patched into one room, and the journal that makes a
# pass something you can play again.
#
#   ruby dilla.rb live set chord_based_beats     one pass of a set
#   ruby dilla.rb live set sampled_based_beats
#   LIVE_VOICING=up ruby dilla.rb live set sampled_based_beats   the 08-31 voicings
#   ruby dilla.rb live set ambient_pads
#   ruby dilla.rb live set interlude|long_form|minimal|gospel   named sets
#   ruby dilla.rb live recall                    the last twenty passes
#   ruby dilla.rb live recall 41205993           play that one again
#   ruby dilla.rb live recall 41205993 keep      render it to demo.wav and add it to the catalogue
#   ruby dilla.rb live recall 41205993 LIVE_ROOM=dry   the take, with one choice changed
#   ruby dilla.rb live catalogue                 the kept takes, titled, in order
#   ruby dilla.rb live recall keep               keep the last pass played
#   ruby dilla.rb live broadcast [set]           all three in turn, or one all night
#   ruby dilla.rb live dig                       fill samples/chopped/ from project/crate.yml
#   ruby dilla.rb live ab <set> KNOB=value       three arms of one seed, level-matched, interleaved
#
#   ruby dilla.rb live knobs                     every LIVE_ knob a set reads
#   ruby dilla.rb live cue [skip <slug>]         the next beds, and passing one over
#   ruby dilla.rb live star <slug> [off]         mark a rack above every score
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
  # tape. A directory under samples/drums/ qualifies if it has all three roles;
  # the ghost is the snare played quiet.
  KIT_ROLES = %w[kick snare hat].freeze

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

    dir = File.expand_path(want, File.join(D, "samples", "drums"))
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

  # Through worth_doc, which is the one read of sample_worth.json: this opened
  # the same file a second way, so a missing or unparseable file had two
  # rescues to get wrong and the scores and the stars could disagree about
  # whether it was there.
  def worth = @worth ||= worth_doc["slugs"] || {}

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
    if (want = ENV["LIVE_BED"].to_s) && !want.empty?
      pinned = beds.find { |b| slug_of(b) == want }
      abort "no such bed: #{want}" unless pinned

      return [pinned, want, worth.fetch(want, nil)]
    end
    bed = bed_queue(beds).first
    [bed, slug_of(bed), worth.fetch(slug_of(bed), nil)]
  end

  def slug_of(bed) = File.basename(File.dirname(bed))

  # Every bed in the order the rig would play them. A starred rack outranks any
  # score, because the operator saying "this one" is the better judgement, and
  # two equally stale beds go in that same order. The order draws nothing: a draw
  # here from the pass stream would shift every choice after it whenever the bed
  # is pinned on replay, which was measured before the tiebreak left the stream.
  def bed_queue(beds = Dir.glob(File.join(beds_dir, "*", "loop.wav")))
    beds = in_key(beds)
    ranked = beds.sort_by { |b| -(starred.include?(slug_of(b)) ? 2.0 : worth.fetch(slug_of(b), 0.35).to_f) }
    pool = ranked.size >= 8 ? ranked.first((ranked.size * 0.5).ceil) : ranked
    pool |= ranked.select { |b| starred.include?(slug_of(b)) }
    seen = recency
    pool.sort_by { |b| [seen.fetch(slug_of(b), -1), ranked.index(b)] }
  end

  # The chop registry's row for each rack: its key, its source and its rights.
  def bed_rows = Array(RadioChop.registry["loops"]).to_h { |row| [row["slug"].to_s, row] }

  # LIVE_KEY="A minor" keeps the beds whose chopped key it names -- every rack
  # carries one, and two records under one harmony need it.
  def in_key(beds)
    want = ENV.fetch("LIVE_KEY", "").strip.downcase
    return beds if want.empty?

    rows = bed_rows
    keyed = beds.select { |b| rows.dig(slug_of(b), "key").to_s.downcase == want }
    known = rows.values.filter_map { |row| row["key"] }.uniq.sort
    abort "LIVE_KEY: no bed in #{want} — the rack has #{known.join(', ')}" if keyed.empty?
    keyed
  end

  # What a pass owes the record under it, printed with the pass, so a set that
  # plays someone's work names it without being asked.
  def credit(slug)
    row = bed_rows.fetch(slug.to_s, {})
    parts = [row["source_label"] || row["source"], row["rights"], row["url"]].compact.map(&:to_s).reject(&:empty?)
    parts.empty? ? nil : parts.join(" — ")
  end

  # The racks the operator marked, in sample_worth.json beside the scores.
  def starred = Array(worth_doc["starred"])

  def worth_doc
    JSON.parse(File.read(WORTH))
  rescue StandardError
    {}
  end

  #   ruby dilla.rb live star <slug>       mark a rack; it outranks every score
  #   ruby dilla.rb live star <slug> off   unmark it
  def star!(argv)
    slug = argv.shift or abort "usage: ruby dilla.rb live star <slug> [off]"
    doc = worth_doc
    list = Array(doc["starred"])
    list = argv.include?("off") ? list - [slug] : (list | [slug])
    DillaFrozen.write_json(WORTH, doc.merge("starred" => list.sort))
    puts "starred: #{list.empty? ? 'none' : list.sort.join(' ')}"
  end

  # The next beds, in order, and a way to say no to one.
  #
  #   ruby dilla.rb live cue               the five the rig plays next
  #   ruby dilla.rb live cue skip <slug>   send one to the back of the queue
  #
  # A skip is a journal line the recency reader counts as played, so the rig
  # passes it over as it would a bed it has just played -- one history, not a
  # second list of rejections to reconcile with it.
  def cue!(argv)
    if argv.first == "skip"
      slug = argv[1] or abort "usage: ruby dilla.rb live cue skip <slug>"
      journal!(at: Time.now.utc.iso8601, cue: "skip", bed: slug)
      puts "skipped #{slug}"
    end
    rows = bed_rows
    bed_queue.first(5).each_with_index do |bed, i|
      slug = slug_of(bed)
      puts format("  %d  %-32s sw %.2f  %-10s %s", i + 1, slug, worth.fetch(slug, 0.35).to_f, rows.dig(slug, "key"), starred.include?(slug) ? "starred" : "")
    end
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
    want, range = [pinned_bpm, 40..200] if pinned_bpm
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
  def place(idx, label, filt, hits, gains = nil)
    out = ["[#{idx}:a]#{filt}[#{label}_s]"]
    out << "[#{label}_s]asplit=#{hits.size}#{(0...hits.size).map { |k| "[#{label}x#{k}]" }.join}"
    # adelay refuses a negative delay, and the jitter that makes the drums drunk
    # can push a hit on the one below zero. Clamped here rather than at every call
    # site, so the graph either builds or it does not.
    hits.each_with_index do |ms, k|
      d = [ms, 0].max.round
      level = gains ? ",volume=#{gains[k]}" : ""
      out << "[#{label}x#{k}]adelay=#{d}|#{d}#{level}[#{label}p#{k}]"
    end
    out << "#{(0...hits.size).map { |k| "[#{label}p#{k}]" }.join}" \
           "amix=inputs=#{hits.size}:normalize=0[#{label}]"
    out
  end

  # Drunk drums. Dilla time is not only a swing setting -- the kick and the snare
  # drag in different directions and by different amounts, and the hats do not
  # agree with either. Appends its own sources and returns the index of the
  # crackle. On the synthesised kit the hats and the record noise are the same
  # long pink generator read twice: 0.006 amplitude pink through a 7.2 kHz
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
    seeds = dir ? { crackle: s.call(3) } : { kick_noise: s.call(1), hat_noise: s.call(2), crackle: s.call(3) }
    hits = kit_hits(beat: beat, bar: bar, step: step, sxt: sxt)
    crackle_i = dir ? sampled_kit!(dir, inputs, graph, hits, beat, seeds, total) : synth_kit!(n, inputs, graph, hits, beat, seeds, total)
    graph << "[kit_raw]#{console(set, :kit)}[kit]"
    { hits: hits, crackle_i: crackle_i }
  end

  # Where each hit lands, in ms. The jitter draws come off the pass stream in
  # the order every journalled take drew them; the groove moves hits by table
  # values and draws nothing.
  def kit_hits(beat:, bar:, step:, sxt:)
    jit = ->(ms) { (rand * ms * 2 - ms).round(1) }
    dna = groove_dna
    hat_swing = dna ? swing_ms(dna[:swing], step) : 34
    {
      kick: [0.0, (bar / 2 + step)].each_with_index.map { |t, k| [(t * 1000).round + jit.call(9) + dna_offset(dna, :kick_offset_ms, k), 0].max },
      snare: [beat, beat * 3].map { |t| (t * 1000).round + 22 + jit.call(7) }, # behind the grid
      ghost: [(beat * 2 + sxt), (beat * 3 + sxt * 3)].map { |t| (t * 1000).round + jit.call(14) },
      hat: (0...8).map { |i| (i * step * 1000).round + (i.odd? ? hat_swing : 0) + jit.call(6) + dna_offset(dna, :hat_offset_ms, i) },
    }
  end

  # Swing that is a swing: the off-eighth lands at the groove's percentage of
  # the pair, so it scales with the tempo. 50 is straight; donuts' 61 puts the
  # off-hat 22% of an eighth late.
  def swing_ms(percent, step) = (((percent / 50.0) - 1.0) * step * 1000).round(1)

  def dna_offset(dna, key, index) = dna ? dna.fetch(key)[index % dna.fetch(key).size] : 0

  # LIVE_GROOVE names a row of the engine's GROOVE_DNA -- donuts, the engine's
  # own default, unless told -- or drunk, the flat 34 ms the sets played before
  # the table was read, which a take kept under it replays with.
  def groove
    want = ENV.fetch("LIVE_GROOVE", "donuts")
    names = ["drunk", *DillaComposition::GROOVE_DNA.keys.map(&:to_s)]
    abort "no groove #{want.inspect} — have #{names.join(', ')}" unless names.include?(want)

    want
  end

  def groove_dna = groove == "drunk" ? nil : DillaComposition::GROOVE_DNA.fetch(groove.to_sym)

  # How hard each hit lands. The DNA's velocity curve is per beat of the bar, so
  # a hit takes the level of the beat it falls in; the ghost's density scales how
  # loud the ghosts sit under it. Velocity is the half of Dilla time the ear
  # reads as a person, and drunk has none.
  def velocities(hits, beat)
    dna = groove_dna or return {}
    curve = dna.fetch(:velocity_curve)
    hits.to_h do |role, times|
      gains = times.map { |ms| curve[((ms / 1000.0) / beat).floor % curve.size] }
      [role, role == :ghost ? gains.map { |g| (g * dna.fetch(:ghost_density)).round(3) } : gains]
    end
  end

  def synth_kit!(n, inputs, graph, hits, beat, seeds, total)
    inputs << "-f lavfi -t 0.32 -i sine=f=52:d=0.32"
    inputs << "-f lavfi -t 0.24 -i anoisesrc=c=pink:d=0.24:seed=#{seeds[:kick_noise]}"
    inputs << "-f lavfi -t 0.05 -i anoisesrc=c=white:d=0.05:seed=#{seeds[:hat_noise]}"
    inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.006:seed=#{seeds[:crackle]}"
    v = velocities(hits, beat)
    graph.concat place(n, "kk", "volume=1.9,afade=t=out:st=0.015:d=0.24,lowpass=f=180," \
                                "acrusher=bits=12:mode=log:aa=1", hits[:kick], v[:kick])
    graph.concat place(n + 1, "sn", "volume=1.5,afade=t=out:st=0.004:d=0.19," \
                                    "bandpass=f=1900:width_type=h:w=2600,volume=1.4", hits[:snare], v[:snare])
    graph.concat place(n + 2, "gh", "volume=0.24,afade=t=out:st=0.003:d=0.09," \
                                    "bandpass=f=2400:width_type=h:w=1800", hits[:ghost], v[:ghost])
    graph.concat place(n + 3, "hh", "volume=0.26,afade=t=out:st=0.002:d=0.048,highpass=f=7200", hits[:hat], v[:hat])
    graph << "[kk][sn][gh][hh]amix=inputs=4:weights=2.8 2.4 1.1 1.0:normalize=0[kit_raw]"
    n + 3
  end

  # A recorded kit, one input per file. A role's files are its own name and any
  # numbered takes beside it -- kick.wav, kick_2.wav -- dealt to its hits in
  # turn, so the second kick of the bar is the second body when there is one and
  # no waveform repeats while another take waits: a kit, not a trigger. The
  # ghost is the snare played quiet and short, because that is what a ghost note
  # is, so a kit needs no ghost file. A synthesised hit needs a filter to become
  # a drum and a recorded one already is one, so it gets almost nothing on the
  # way in; the shaping happens after the mix, in the 1260 and the console.
  KIT_GAINS = { kick: ["kk", "volume=1.5"], snare: ["sn", "volume=1.2"], hat: ["hh", "volume=0.4"] }.freeze

  def sampled_kit!(dir, inputs, graph, hits, beat, seeds, total)
    v = velocities(hits, beat)
    trims = kit_trims(dir)
    snare_i = nil
    labels = KIT_GAINS.flat_map do |role, (label, gain)|
      takes = role_takes(dir, role)
      takes.each_with_index.map do |take, t|
        inputs << "-i #{take.shellescape}"
        snare_i ||= inputs.size - 1 if role == :snare
        mine = hits[role].each_index.select { |k| k % takes.size == t }
        graph.concat place(inputs.size - 1, "#{label}#{t}", "#{gain},volume=#{trims.fetch(role)}dB",
                           mine.map { |k| hits[role][k] }, v[role] && mine.map { |k| v[role][k] })
        "[#{label}#{t}]"
      end
    end
    graph.concat place(snare_i, "gh", "volume=0.42,volume=#{trims.fetch(:snare)}dB,afade=t=out:st=0.02:d=0.1",
                       hits[:ghost], v[:ghost])
    graph << "#{labels.join}[gh]amix=inputs=#{labels.size + 1}:normalize=0,volume=1.3[kit_raw]"
    inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.006:seed=#{seeds[:crackle]}"
    inputs.size - 1
  end

  def role_takes(dir, role)
    Dir.glob(File.join(dir, "#{role}{,_[0-9]*}.wav")).sort_by { |path| [File.basename(path).length, path] }
  end

  # How far each role is from the kit the sampled weights were set against,
  # measured from the files every pass rather than stored: a new kit is in level
  # the first time it plays, and there is no table of trims to fall out of date.
  # Peaks, because the attack is what a one-shot is heard by. The reference is
  # custom, the one complete recorded kit on disk when the weights were set:
  # kick -4.7, snare -6.8, hat -4.9 dBFS.
  KIT_REFERENCE_PEAK = { kick: -4.7, snare: -6.8, hat: -4.9 }.freeze

  def kit_trims(dir)
    KIT_REFERENCE_PEAK.to_h do |role, reference|
      out = `#{FF} -hide_banner -nostats -i #{role_takes(dir, role).first.shellescape} -af volumedetect -f null - 2>&1`
      peak = out[/max_volume: (-?[\d.]+) dB/, 1]
      [role, peak ? (reference - peak.to_f).round(2) : 0.0]
    end
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
    shape = arranged(set, bar, total, drop).to_h { |bus, points| [bus, muted.include?(bus.to_s) ? [[0, 0.0]] : points] }
    marks = shape.flat_map { |bus, points| points.drop(1).map { |at, gain| [at, "#{bus} #{gain.zero? ? 'out' : "to #{gain}"}"] } }
    @transport = { bar: bar, total: total, marks: marks.sort_by(&:first) }
    shape
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

  # Loudness for where the pass is going. Unset, a set ends as tuned -- the
  # normaliser, a fixed volume and a limiter, which lands the three sets between
  # -10 and -14 LUFS. LIVE_LUFS=-16 adds ffmpeg's loudnorm after all of it, aimed
  # at that integrated loudness with a -1 dBTP ceiling, for a stream or a platform
  # that asks for a number. Integrated LUFS weighs the whole mix, so it reads
  # speech over music as louder than an ear does; a set with a voice in it wants
  # its target a few LU lower.
  def loudness
    want = ENV.fetch("LIVE_LUFS", "").to_s
    return "" if want.empty?

    value = Float(want, exception: false)
    abort "LIVE_LUFS=#{want} is not a loudness between -30 and -6" unless value&.between?(-30, -6)
    "loudnorm=I=#{value}:TP=-1.0:LRA=11,"
  end

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
    return render_to!(cmd, dest) unless dest.empty?

    pid = Process.spawn("/bin/zsh", "-c",
                        "#{cmd} -f wav - 2>/dev/null | #{FFPLAY} -nodisp -autoexit -loglevel quiet -i - 2>/dev/null")
    ticker = Thread.new { transport!(Process.clock_gettime(Process::CLOCK_MONOTONIC)) }
    Process.wait(pid)
    ticker.kill
    warn ""
    exit($?.exitstatus || 1) unless $?.success?
  end

  # A visible transport: the bar, how many there are, and the next change in the
  # arrangement, redrawn on one line every bar while a pass plays. The banner
  # printed once and then ninety-six seconds passed in silence.
  def transport!(started)
    t = @transport or return
    loop do
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      $stderr.print "\r#{transport_line(elapsed, t)}"
      sleep t[:bar]
    end
  end

  def transport_line(elapsed, transport)
    bar = transport[:bar]
    bars = (transport[:total] / bar).ceil
    now = [(elapsed / bar).floor + 1, bars].min
    upcoming = transport[:marks].find { |at, _| at > elapsed }
    next_change = upcoming ? "  #{upcoming.last} in #{((upcoming.first - elapsed) / bar).ceil} bar(s)" : ""
    format("bar %d/%d%s   ", now, bars, next_change)
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
    FileUtils.rm_f(partial) unless ok # the fragment this call just wrote
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
  # The tempo, tapped or typed: LIVE_BPM pins the chord set's count, and on a bed
  # set it reads the record's grid at the whole number of bars nearest to it --
  # the record's own length still decides the bar, so a pinned tempo halves or
  # doubles a reading rather than stretching it. The chord set's draw is made
  # either way, so the stream moves no later choice.
  def pinned_bpm
    want = ENV.fetch("LIVE_BPM", "").to_s
    return nil if want.empty?

    value = Float(want, exception: false)
    abort "LIVE_BPM=#{want} is not a tempo between 40 and 200" unless value&.between?(40, 200)
    value
  end

  #   ruby dilla.rb live tap     press Enter on the beat; q and Enter stops
  #
  # Sometimes the record is wrong. The tapped figure is what LIVE_BPM takes.
  def tap!
    times = []
    warn "tap Enter on the beat, q to finish"
    while (line = $stdin.gets) && line.strip != "q"
      times << Process.clock_gettime(Process::CLOCK_MONOTONIC)
      bpm = tap_bpm(times)
      warn(bpm ? "LIVE_BPM=#{bpm}" : "keep tapping")
    end
  end

  # The median gap, so one late tap does not move the count.
  def tap_bpm(times)
    return nil if times.size < 3

    gaps = times.each_cons(2).map { |a, b| b - a }.sort
    (60.0 / gaps[gaps.size / 2]).round(1)
  end

  def pinned_drag(drawn)
    want = ENV.fetch("LIVE_DRAG", "").to_s
    return drawn if want.empty?

    value = Float(want, exception: false)
    abort "LIVE_DRAG=#{want} is not a ratio between 0.5 and 1.0" unless value&.between?(0.5, 1.0)
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
    bpm = pinned_bpm || (82 + rand * 12).round(1)
    beat = (60.0 / bpm).round(4)
    bar = (beat * 4).round(4)
    step = (beat / 2).round(4)
    sxt = (beat / 4).round(4)
    chord_s = (bar * chord_bars(chords.size)).round(4)

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
             "alimiter=limit=0.98:level=disabled,#{loudness}" \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      named: @named, at: Time.now.utc.iso8601, seed: seed, set: "chord_based_beats", seconds: total, bed: nil, progression_name: name.to_s,
      progression: symbols, bpm: bpm, bar_s: bar, chord_s: chord_s, chord_bars: ENV["LIVE_CHORD_BARS"], kit_cycle: kit_cycle, form: form,
      bus_patch: ENV['LIVE_BUS_PATCH'], muted: muted.join(","),
      weights: weights("chord_based_beats"),
      drums: { kick_ms: hits[:kick], snare_ms: hits[:snare], ghost_ms: hits[:ghost], hat_ms: hits[:hat] }, groove: groove,
      **console_record("chord_based_beats"), lufs: ENV["LIVE_LUFS"], rig: "dilla.rb live set chord_based_beats"
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
             "alimiter=limit=0.98:level=disabled,#{loudness}" \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      named: @named, at: Time.now.utc.iso8601, seed: seed, set: "sampled_based_beats", shareable: shareable?("bed" => slug), seconds: total, bed: slug, credit: credit(slug), sample_worth: sw,
      bpm: g[:bpm], bpm_pin: pinned_bpm, drag: drag, bars_in_loop: g[:bars_in_loop], voicing: choice, progression: prog,
      chop_at: slice_at, reversed: reverse, bar_s: bar, form: form, hocket: voice_of.values.max.to_i + 1,
      bus_patch: ENV['LIVE_BUS_PATCH'], muted: muted.join(","),
      weights: weights("sampled_based_beats"),
      drums: { kick_ms: hits[:kick], snare_ms: hits[:snare], ghost_ms: hits[:ghost], hat_ms: hits[:hat] }, groove: groove,
      **console_record("sampled_based_beats"), lufs: ENV["LIVE_LUFS"], rig: "dilla.rb live set sampled_based_beats"
    )

    play!(inputs, graph,
          "▶ sampled  #{slug}  sw=#{format('%.2f', sw.to_f)}  #{g[:bpm]}bpm " \
          "(#{g[:bars_in_loop]}bar loop, drag #{drag})  " \
          "#{prog.map { |c| c ? "#{c[0]}#{c[1]}" : '.' }.join(' ')}" \
          "#{reverse ? '  REV' : ''}  chop@#{slice_at}s#{credit(slug) ? "\n  from #{credit(slug)}" : ''}")
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
             "alimiter=limit=0.97:level=disabled,#{loudness}" \
             "aformat=sample_rates=44100:channel_layouts=stereo[out]"

    journal!(
      named: @named, at: Time.now.utc.iso8601, seed: seed, set: "ambient_pads", shareable: shareable?("bed" => slug), seconds: total, bed: slug, credit: credit(slug), sample_worth: sw,
      bpm: g[:bpm], bpm_pin: pinned_bpm, drag: drag, bars_in_loop: g[:bars_in_loop], progression: prog,
      chop_at: slice_at, hold_s: hold, bar_s: bar, drums: nil, form: form,
      copy_machine: copies('ambient_pads'), voice_stack: voice_stack_plan.size, bus_patch: ENV['LIVE_BUS_PATCH'], muted: muted.join(","),
      weights: weights("ambient_pads"),
      **console_record("ambient_pads"), lufs: ENV["LIVE_LUFS"], rig: "dilla.rb live set ambient_pads"
    )

    play!(inputs, graph,
          "▶ pads  #{slug}  sw=#{format('%.2f', sw.to_f)}  #{g[:bpm]}bpm " \
          "(#{g[:bars_in_loop]}bar loop, drag #{drag})  hold #{hold}s  " \
          "#{prog.map { |semi, v| "#{semi}#{v}" }.join(' ')}  chop@#{slice_at}s#{credit(slug) ? "\n  from #{credit(slug)}" : ''}")
  end

  # Sets named for what they are, each one of the three with its knobs set. A
  # named set is data rather than a fourth arrangement, so everything a set can
  # do stays in one place; a knob exported by hand still wins over the name's.
  #
  #   interlude   thirty-one seconds of the sampled set: one idea, no arrangement
  #               reaching it. Donuts is thirty-one pieces in forty-three minutes.
  #   long_form   twenty minutes of pads across the soul_32 form, to leave
  #               running; rendered whole, its graph peaked at 86 MB.
  #   minimal     one voice: the chord set with no kit, no crackle and no room --
  #               the control every addition is measured against.
  #   gospel      the eight-bar climb as the whole arrangement, a bar a chord at 72.
  #
  # Flip and DFAM are not named sets, and the reason is where their sound is
  # made: SampleFlip and DfamEngine are per-sample Ruby that write audio files,
  # and a set is one real-time ffmpeg graph whose only file is demo.wav. The
  # sampled set already plays the crate's slices against chords, which is the
  # flip; the engine keeps DFAM for its note-plan renders.
  NAMED_SETS = {
    "interlude" => ["sampled_based_beats", { "LIVE_LENGTH" => "31" }],
    "long_form" => ["ambient_pads", { "LIVE_LENGTH" => "1200", "LIVE_FORM" => "soul_32" }],
    "minimal" => ["chord_based_beats", { "LIVE_ROOM" => "dry", "LIVE_MUTE" => "kit,crackle" }],
    "gospel" => ["chord_based_beats", { "LIVE_PROGRESSION" => "eight_bar_gospel_climb", "LIVE_BPM" => "72",
                                        "LIVE_CHORD_BARS" => "1" }],
  }.freeze

  def set_names = SETS + NAMED_SETS.keys

  def play_set!(name)
    abort "no set #{name.inspect} — have #{set_names.join(', ')}" unless set_names.include?(name.to_s)

    base, knobs = NAMED_SETS.fetch(name.to_s, [name.to_s, {}])
    knobs.each { |knob, value| ENV[knob] ||= value }
    @named = NAMED_SETS.key?(name.to_s) ? name.to_s : nil
    send(:"#{base}!")
  end

  # How many bars each chord of the chord set holds: LIVE_CHORD_BARS, or half a
  # bar when eight chords share a phrase and a bar when four do.
  def chord_bars(count)
    want = ENV.fetch("LIVE_CHORD_BARS", "").to_s
    return count == 8 ? 0.5 : 1.0 if want.empty?

    value = Float(want, exception: false)
    abort "LIVE_CHORD_BARS=#{want} is not a number of bars from 0.25 to 4" unless value&.between?(0.25, 4)
    value
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

  # The catalogue: the passes worth keeping, in the order they were kept, each
  # with a title and whether it may leave the building. The journal is a log of
  # everything played; this is the subset that is a record.
  #
  # A take is not a wav. demo.wav is the only audio dilla keeps and the next
  # render replaces it, so what makes a take survive is its line here: the seed
  # and every choice, which rebuild it on any machine that has the crate.
  #
  # So a kept take has no stems. A stem is an audio file, and the one audio file
  # is demo.wav; and every bus of a take is already one recall away -- the take
  # with LIVE_MUTE naming the others is that bus alone, rendered from the same
  # seed, which is a stem that cannot go stale or go missing.
  CATALOGUE = File.join(D, "project", "liveset_catalogue.json")

  def catalogue_path = ENV.fetch("LIVE_CATALOGUE", CATALOGUE)
  def catalogue = File.file?(catalogue_path) ? JSON.parse(File.read(catalogue_path)) : []

  def catalogue!(row, overrides = [], measured = {})
    entry = { "title" => title_for(row), "kept_at" => Time.now.utc.iso8601, "shareable" => shareable?(row),
              "overrides" => overrides, "mix" => measured, "row" => row }
    DillaFrozen.write_json(catalogue_path, catalogue + [entry])
    entry
  end

  def render_take!(env, row)
    abort "keep: the pass did not render" unless system(env, RbConfig.ruby, File.join(D, "dilla.rb"), "live", "set", row["set"].to_s)
  end

  def score_take = MixScore.score(DEMO)

  # A take scores itself before it is kept. MixScore measures the render against
  # the two takes kept on their merits -- loudness, loudness range, the kick
  # against the mids, the sub against the mids, the cymbal crest and the tilt --
  # and a pass that misses three of the six, or misses one of them by more than
  # 3 dB, is not catalogued: the rig should not tell the catalogue a take is a
  # record when its own measurement says otherwise. The numbers go in the entry
  # either way, so a kept take carries what it measured. LIVE_KEEP_ANY=1 keeps it
  # regardless, which is how a take the ear likes and the table does not gets in.
  KEEP_MISS_LIMIT = 3.0

  def keep!(row, overrides, scored)
    missed = scored.reject { |_, _, miss, _| miss.zero? }
    bad = missed.size >= 3 || missed.any? { |_, _, miss, _| miss.abs > KEEP_MISS_LIMIT }
    measured = scored.to_h { |key, value, miss, _| [key.to_s, { "value" => value, "miss" => miss }] }
    missed.each { |key, value, miss, spec| warn format("  %-14s %7.2f %s  %+.2f outside %s", key, value, spec[:unit], miss, spec[:range]) }
    if bad && ENV["LIVE_KEEP_ANY"] != "1"
      abort "keep: the take misses its window -- render it again (LIVE_LUFS=-16 is the usual answer), " \
            "or keep it anyway with LIVE_KEEP_ANY=1"
    end

    entry = catalogue!(row, overrides, measured)
    warn "kept \"#{entry['title']}\" -> demo.wav; project/liveset_catalogue.json holds the record that rebuilds it" \
         "#{entry['shareable'] ? '' : ' (not for release: its record is not cleared)'}"
    entry
  end

  def catalogue_show!
    entries = catalogue
    return puts("nothing kept yet -- ruby dilla.rb live recall <seed> keep") if entries.empty?

    entries.each_with_index do |e, i|
      puts format("  %2d  %-44s %-11s %s", i + 1, e["title"], e.dig("row", "seed"), e["shareable"] ? "" : "not for release")
    end
  end

  # A title rather than a seed: what the take is made of, named the way a
  # person would name it -- the progression for the chord set, the record for a
  # bed set -- with the set and seed after it so two takes of one record differ.
  def title_for(row)
    subject = row["progression_name"] || row["credit"].to_s.split(" — ").first || row["bed"] || row["set"]
    words = subject.to_s.sub(/_\d+\z/, "").tr("_", " ").split.map(&:capitalize).join(" ")
    "#{words} (#{row['named'] || row['set'].to_s.split('_').first} #{row['seed']})"
  end

  # Whether a take may be shared. A pass over a bed is as releasable as the
  # record under it, and the rack's rights say so: a YouTube rip or an off-air
  # capture is unlicensed, and a bed with no rights recorded is treated the same,
  # because nobody has said otherwise. The chord set plays no record.
  def shareable?(row)
    return true unless row["bed"]

    rights = bed_rows.dig(row["bed"].to_s, "rights").to_s
    !rights.empty? && !rights.match?(/unlicensed|not cleared/i)
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
    "LIVE_KIT_CYCLE" => ["kit_cycle", "phrase"], "LIVE_FORM" => ["form", nil], "LIVE_MUTE" => ["muted", nil], "LIVE_WEIGHTS" => ["weights", nil], "LIVE_DRAG" => ["drag", nil], "LIVE_BPM" => ["bpm_pin", nil], "LIVE_GROOVE" => ["groove", "drunk"], "LIVE_CHORD_BARS" => ["chord_bars", nil], "LIVE_LUFS" => ["lufs", nil],
    "LIVE_COPY_MACHINE" => ["copy_machine", "0"], "LIVE_VOICE_STACK" => ["voice_stack", "1"], "LIVE_HOCKET" => ["hocket", "1"],
    "LIVE_BUS_PATCH" => ["bus_patch", nil],
  }.freeze

  def recall_env(row)
    pins = RECALLED.to_h { |knob, (key, legacy)| [knob, row.key?(key) ? knob_value(row[key]) : legacy] }
    { "LIVE_SEED" => row["seed"].to_s }.merge(pins)
  end

  # Every knob a set reads, and what it does, printed by `live knobs`. A set is
  # steered from here rather than by editing it; a knob read and not listed
  # fails the suite.
  KNOB_DOCS = {
    "LIVE_SEED" => "the pass: every drawn choice, replayed",
    "LIVE_OUT" => "live improvise|progression|patch: write the stream to this file instead of the sound card",
    "LIVE_LENGTH" => "the block in seconds (96 for the beat sets, 180 for the pads)",
    "LIVE_ROOM" => "the console: #{ROOMS.join('|')}",
    "LIVE_FORM" => "a FORM_PRESETS name, arranged across the block by the engine's layers",
    "LIVE_MUTE" => "comma list of #{MUTABLE.join(',')} (DRUMS=0 mutes the kit)",
    "LIVE_WEIGHTS" => "bus=weight pairs, how loud each bus meets the others",
    "LIVE_BED" => "pin the record a bed set plays, by rack slug",
    "LIVE_KEY" => "only beds chopped in this key, as the registry spells it (A minor)",
    "LIVE_DRAG" => "pin how far under its pitch the record runs, 0.5..1.0",
    "LIVE_BPM" => "pin the tempo, 40..200; a bed set reads its grid nearest to it (live tap finds one)",
    "LIVE_KIT" => "a directory under samples/drums with every kit role, or synth",
    "LIVE_GROOVE" => "a GROOVE_DNA row (donuts default) or drunk, the flat swing a take kept before it",
    "LIVE_KIT_CYCLE" => "bar (default) or phrase, how often the chord set's kit repeats",
    "LIVE_PROGRESSION" => "pin the chord set's progression by name",
    "LIVE_CHORD_BARS" => "bars per chord in the chord set, 0.25..4 (half a bar for eight chords, one for four)",
    "LIVE_VOICING" => "down (default) or up, the sampled set's voicing tables",
    "LIVE_COPY_MACHINE" => "copies in the cloud under a bed, 0..8 (4 on the pads)",
    "LIVE_VOICE_STACK" => "voices per held pad slice, 1..7 (3)",
    "LIVE_HOCKET" => "voices the sampled phrase is dealt across, 1..4 (3)",
    "LIVE_BUS_PATCH" => "a bus to carry a random modulation patch",
    "LIVE_LUFS" => "integrated loudness to finish at, -30..-6 (unset: as tuned)",
    "LIVE_KEEP_ANY" => "1 keeps a take the mix score says misses its window",
    "LIVE_RENDER_TO" => "demo.wav, or - for a wav down stdout; unset plays",
    "LIVE_CATALOGUE" => "the catalogue recall keep adds to, when it must not be project/liveset_catalogue.json",
    "LIVE_JOURNAL" => "the journal a run writes, when it must not be the catalogue's",
    "LIVE_BEDS_DIR" => "the rack a bed set picks from",
  }.freeze

  def knobs!
    KNOB_DOCS.each { |knob, doc| puts format("  %-18s %s", knob, doc) }
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
    # A take reopens as parameters: LIVE_ROOM=dry after the seed replays the take
    # with that one choice changed, which is what editing a set means here.
    overrides, argv = argv.partition { |a| a.match?(/\ALIVE_[A-Z_]+=/) }
    unknown = argv.reject { |a| a.match?(/\A\d+\z/) }
    abort("recall: unknown word #{unknown.join(' ')} -- see ruby dilla.rb live recall help") if unknown.any?
    seed = argv.shift
    rows = passes
    return show(rows) if seed.nil? && !keep

    row = seed ? rows.reverse.find { |r| r["seed"].to_s == seed.to_s } : rows.last
    abort(seed ? "no pass with seed #{seed}" : "nothing in the journal yet") unless row

    env = recall_env(row).merge(overrides.to_h { |o| o.split("=", 2) })
    label = "#{row['set']} #{row['seed']}"
    unless keep
      warn "replaying #{label}"
      return exec(env, RbConfig.ruby, File.join(D, "dilla.rb"), "live", "set", row["set"].to_s)
    end
    warn "rendering #{label} to demo.wav"
    render_take!(env.merge("LIVE_RENDER_TO" => DEMO), row)
    keep!(row, overrides, score_take)
  end

  # Pass after pass until interrupted. A pass that exits non-zero moves on to the
  # next set rather than ending the night. Hard cuts between sets: a set that
  # crossfades into the next is catalogue item 11, a set of its own. A misspelt
  # set would otherwise fail every 0.2 seconds all night, so it is refused first.
  #
  # It stops cleanly. Each pass runs in its own process group, so Ctrl-C reaches
  # the rig and not the pass: the first lets the pass play to its end and then
  # stops the night, the second stops the pass now. Stopping meant killing
  # processes before, mid-bar.
  def broadcast!(name = nil)
    abort "broadcast: no set named #{name} -- have #{set_names.join(', ')}" if name && !set_names.include?(name)

    @stopping = false
    sets = name ? [name] : ROTATION
    sets.cycle do |set|
      pid = Process.spawn(RbConfig.ruby, File.join(D, "dilla.rb"), "live", "set", set, pgroup: true)
      trap("INT") { interrupt!(pid) }
      Process.wait(pid)
      break if @stopping

      sleep 0.2
    end
  end

  def interrupt!(pid)
    if @stopping
      Process.kill("TERM", -pid)
    else
      @stopping = true
      warn "\nstopping when this pass ends -- Ctrl-C again to stop now"
    end
  rescue Errno::ESRCH
    nil
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
  AB_EXPORT = %w[MASTER/tools/dilla MASTER/lib MASTER/Gemfile MASTER/Gemfile.lock].freeze

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

    crate.each_with_index do |entry, i|
      slug = RadioChop.crate_slug(entry["title"])
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

# The synthesiser, played live: AnalogSynth's patches and the Model D panels,
# generated a block at a time and piped to the sound card as they are made.
#
#   ruby dilla.rb live default                    MASTER's main sound: liveset.rb, until stopped
#   ruby dilla.rb live improvise [family=moog] [pad=<patch>] [seconds]
#   ruby dilla.rb live progression [name] [pads=a,b] [family=moog] [loops=N] [seconds]
#   ruby dilla.rb live patch <name>               the patch's own phrase
#   ruby dilla.rb live knob <name> <+0.3|-0.3|0.8> [seconds]
#   ruby dilla.rb live morph <patch> [seconds]
#   ruby dilla.rb live stop | status
#   ruby dilla.rb live say "slowly open the filter"
#
# Two modes are the sound the operator approved on 2026-09-24 and are played
# here as they were heard: `progression soul_jazz_six` (a pad changing every
# two chords over moog_bass, cutoff breathing on a 23 s sine and resonance on
# 31 s) and `improvise` (a walk over soul-jazz harmony with a late bass, leads
# that come and go, pad changes every three to six chords, and cutoff,
# resonance and detune as slow random walks). data/live.yml holds all of it.
#
# One player at a time. It writes its pid where `stop`, `knob`, `morph` and
# `say` find it, reads the commands they append while it plays, and removes
# the record when it stops, so MASTER can start, steer and stop it from a
# sentence without holding a process of its own.
module LiveSynth
  DATA_FILE = File.join(Livesets::D, "data", "live.yml")
  ENGINE = File.join(Livesets::D, "dilla.rb")
  USAGE = "usage: ruby dilla.rb live improvise|progression [name]|patch <name>|knob <name> <amount> [seconds]|" \
          "morph <patch> [seconds]|stop|status|say \"<sentence>\""

  module_function

  def config = @config ||= YAML.load_file(DATA_FILE)

  def stream = config.fetch("stream")

  def log(message) = $stdout.puts("live0: #{message}")

  def main(argv)
    verb = argv.shift
    options = argv.select { |arg| arg.include?("=") }.to_h { |arg| arg.split("=", 2) }
    words = argv.reject { |arg| arg.include?("=") }
    return knob!(*words) if verb == "knob"

    seconds = words.find { |word| word.match?(/\A\d+(\.\d+)?\z/) }&.to_f
    words.delete_if { |word| word.match?(/\A\d+(\.\d+)?\z/) }
    case verb
    when "default" then standard_default!
    when "improvise" then perform!(Improviser.new(rng: rng!, family: options["family"], pad: options["pad"]), seconds:)
    when "progression"
      perform!(Progression.new(words.first || "soul_jazz_six", rng: rng!, pads: options["pads"]&.split(","),
                               family: options["family"], loops: options["loops"]&.to_i), seconds:)
    when "patch" then perform!(Demo.new(Patches.name!(words.first.to_s), rng: rng!), seconds:)
    when "morph" then log(Session.post!("patch" => Patches.name!(words.first.to_s), "seconds" => seconds))
    when "stop" then log(Session.stop!)
    when "status" then log(Session.status)
    when "say" then log(Say.call(words.join(" ")))
    else abort USAGE
    end
  end

  # `knob cutoff +0.3 20` moves by, `knob cutoff 0.8 20` moves to; the last
  # number is how many seconds the knob takes to get there.
  def knob!(name = nil, amount = nil, seconds = nil)
    abort USAGE unless name && amount

    log(Session.post!("knob" => name, "amount" => amount, "seconds" => seconds&.to_f))
  end

  # MASTER's main sound is liveset.rb beside dilla.rb, the live set the
  # operator froze, and it plays as that file and nothing else: it is
  # recorded as the player and then becomes it, keeping the pid `stop` needs.
  # Its knobs move by themselves; a sentence cannot turn them.
  LIVESET = File.join(Livesets::D, "liveset.rb")

  def standard_default!
    abort "live0: #{LIVESET} is missing" unless File.file?(LIVESET)

    Session.claim!("the standard default (liveset.rb)", steerable: false)
    log("the standard default -- `ruby dilla.rb live stop` to end")
    exec(RbConfig.ruby, "--yjit", LIVESET)
  end

  # Drawn and printed, so a take somebody liked can be played again with
  # LIVE_SEED -- the rule every render here follows.
  def rng!
    seed = (ENV["LIVE_SEED"] || Random.new_seed % 1_000_000_000).to_i
    log("seed #{seed}")
    Random.new(seed)
  end

  def perform!(score, seconds: nil)
    rate = stream.fetch("rate")
    # A score with a console of its own brings its command; the rest play
    # through the tanh master straight to the player, or to LIVE_OUT.
    command = score.player_command(rate, ENV["LIVE_OUT"]) if score.respond_to?(:player_command)
    command ||= ENV["LIVE_OUT"] ? DillaLive.writer_command(ENV["LIVE_OUT"], rate) : DillaLive.player_command(rate)
    abort "live0: no player -- install sox (brew install sox) and ffmpeg" unless command

    Session.claim!(score.describe)
    DillaLive.accelerate!
    stage = Stage.new(rate:, rng: score.rng)
    %w[TERM INT].each { |signal| Signal.trap(signal) { stage.stop! } }
    log("#{score.describe} at #{rate} Hz -- `ruby dilla.rb live stop` to end")
    IO.popen(command, "wb") { |sink| stage.run(score, sink, seconds:) }
    log("stopped, #{stage.meter}")
  rescue Errno::EPIPE
    log("the player closed")
  ensure
    Session.release!
  end

  # The stream through ffmpeg on its way out: `filter` is ["-af", chain] or
  # ["-filter_complex", graph], and what leaves is stereo, to the player or,
  # with dest, to a file. Nil when ffmpeg or a player is missing.
  def through_ffmpeg(channels:, filter:, rate:, dest: nil)
    ffmpeg = DillaLive.which("ffmpeg") or return nil
    input = [ffmpeg, "-loglevel", "error", "-f", "s16le", "-ar", rate.to_s, "-ac", channels.to_s, "-i", "-", *filter]
    return input + ["-y", "-c:a", "pcm_s16le", dest] if dest

    player = DillaLive.player_command(rate) or return nil
    ["sh", "-c", "#{Shellwords.join(input + ['-f', 's16le', '-ar', rate.to_s, '-ac', '2', '-'])} | #{Shellwords.join(player)}"]
  end

  # One stage of a `master` console: a Nasty VCS or a Sonitex STX-1260 built
  # by the livesets' own formulas, or a filter written out.
  def console_stage(stage)
    kind, params = stage.first
    return params if kind == "filter"

    Livesets.public_send(kind.to_sym, **params.transform_keys(&:to_sym))
  end

  # The patches the live side can name: every AnalogSynth patch and every
  # Model D panel, found in a sentence by name or alias.
  module Patches
    module_function

    def names = AnalogSynth::PATCHES.keys.map(&:to_s) + AnalogSynth::ModelD.names

    def name!(name)
      return name if names.include?(name)

      found = find(name.tr("_", " "))
      found.first || abort("live0: no patch #{name} (#{names.join(' ')})")
    end

    def spec(name)
      AnalogSynth::PATCHES[name.to_sym] || AnalogSynth::ModelD.patch(name)
    end

    # What a patch plays when it is given a line to itself.
    def role(name)
      spec = spec(name)
      return :bass if name.match?(/bass|sub/)
      return :lead if spec[:legato] || name.match?(/lead|bell|reed|flute|pluck|lucky/)

      :pad
    end

    def demo(name)
      own = AnalogSynth::ModelD.names.include?(name) && AnalogSynth::ModelD.panel(name)["demo"]
      own || LiveSynth.config.fetch("demos").fetch(role(name).to_s)
    end

    # Phrase => patch, longest phrases first, so "moog bass" is heard before
    # "bass". Model D aliases come first: "moog bass" asks for the panel.
    def phrases
      @phrases ||= begin
        panels = AnalogSynth::ModelD.panels.flat_map do |name, panel|
          [[name.tr("_", " "), name], *Array(panel["aliases"]).map { |word| [word, name] }]
        end
        patches = AnalogSynth::PATCHES.keys.map { |key| [key.to_s.tr("_", " "), key.to_s] }
        (panels + patches).uniq(&:first).sort_by { |phrase, _| -phrase.length }
      end
    end

    # Patches named in the sentence, in the order they are named.
    def find(text)
      text = text.downcase.tr("_", " ")
      taken = []
      hits = phrases.filter_map do |phrase, name|
        at = text =~ /\b#{Regexp.escape(phrase)}\b/
        next unless at && taken.none? { |range| range.cover?(at) }

        taken << (at...(at + phrase.length))
        [at, name]
      end
      hits.sort.map(&:last).uniq
    end
  end

  # The knobs. Each has a base that moves on its own -- a slow sine in a
  # progression, a mean-reverting random walk while improvising -- and an
  # offset a person sets by asking, which travels to where it was asked over
  # the seconds it was given. Values run 0 to 1; a knob nothing moves sits at
  # 0.5, which is where a role's response leaves its patch unchanged in pitch
  # spread and envelope.
  class Knobs
    NAMES = %w[cutoff resonance detune contour dub].freeze
    NEUTRAL = 0.5
    # Detune's reach when a mode's response does not name one: the spread the
    # improviser was approved with.
    DETUNE_SPAN = 0.004

    def initialize(motion, response:, rng:, damping: 0.995, pull: 0.02)
      @motion = motion
      @response = response
      @rng = rng
      @damping = damping
      @pull = pull
      @walks = motion.to_h { |name, how| [name, [how.fetch("start", NEUTRAL).to_f, 0.0]] }
      @offsets = {}
      @pan = LiveSynth.stream.fetch("pan")
    end

    # The knob values for this block. Walks step in the order data/live.yml
    # lists them, which is the order their random draws were approved in.
    def step(dt, clock)
      base = NAMES.to_h { |name| [name, NEUTRAL] }
      @motion.each { |name, how| base[name] = moved(name, how, dt, clock) }
      base.to_h { |name, value| [name, (value + offset(name, clock)).clamp(0.0, 1.0)] }
    end

    # Moves a knob's offset by `by`, or to put the knob at `to`, over seconds.
    def turn(name, clock:, seconds:, by: nil, to: nil)
      raise ArgumentError, "no knob #{name} (#{NAMES.join(' ')})" unless NAMES.include?(name)

      now = offset(name, clock)
      target = to ? now + (to - current(name, clock)) : now + by.to_f
      @offsets[name] = [now, target, clock, [seconds.to_f, 0.001].max]
    end

    # How the knobs bend one voice: its role's cutoff scale and resonance, the
    # detune spread, its side of the stereo field, and the contour amount.
    def shape(voice, knobs)
      response = @response.fetch(voice.role.to_s) { @response.fetch("pad") }
      spec = voice.spec
      base, span = response.fetch("cutoff")
      reach, ceiling = response.fetch("resonance")
      resonance = spec[:resonance] + (knobs["resonance"] * reach)
      { cutoff: spec[:cutoff] * (base + (knobs["cutoff"] * span)),
        resonance: ceiling ? [resonance, ceiling].min : resonance,
        spread: 1.0 + ((knobs["detune"] - 0.5) * response.fetch("detune", DETUNE_SPAN)),
        pan: @pan.fetch(voice.role.to_s), contour: 2.0 * knobs["contour"], }
    end

    private

    # A sine, a walk, or a knob left where it was set.
    def moved(name, how, dt, clock)
      return sine(how, clock) if how.key?("sine_seconds")
      return walk(name, how, dt) if how.key?("speed")

      how.fetch("start", NEUTRAL).to_f
    end

    def sine(how, clock)
      how["centre"] + (how["depth"] * Math.sin((2 * Math::PI * clock / how["sine_seconds"]) + how["phase"]))
    end

    def walk(name, how, dt)
      value, velocity = @walks.fetch(name)
      velocity = (velocity * @damping) + (@rng.rand(-1.0..1.0) * how["speed"] * dt) + ((0.5 - value) * @pull * dt)
      value = (value + (velocity * dt)).clamp(0.0, 1.0)
      @walks[name] = [value, velocity]
      value
    end

    def current(name, clock)
      how = @motion[name]
      base = if how.nil? then NEUTRAL
             elsif how.key?("sine_seconds") then sine(how, clock)
             elsif how.key?("speed") then @walks.fetch(name).first
             else how.fetch("start", NEUTRAL).to_f
             end
      base + offset(name, clock)
    end

    def offset(name, clock)
      from, to, at, seconds = @offsets[name]
      return 0.0 unless from

      from + ((to - from) * ((clock - at) / seconds).clamp(0.0, 1.0))
    end
  end

  # Where the notes come from, the knobs and the clock go through here. It
  # holds the sounding voices, renders each block and hands it to the pipe.
  class Stage
    attr_reader :rate, :rng

    def initialize(rate:, rng:)
      config = LiveSynth.stream
      @rate = rate
      @rng = rng
      @block = config.fetch("block_frames")
      @drive = config.fetch("master_drive")
      @scale = config.fetch("master_scale")
      @drift = config.fetch("note_drift_cents")
      @tail = config.fetch("tail_seconds")
      @fade = config.fetch("stop_fade_seconds")
      @voices = []
      @inbox = Session::Inbox.new
      @spent = 0.0
      @played = 0.0
    end

    # One note. `rng` is the stage's own unless a mode seeds its notes itself.
    def note(midi, spec, start, held, gain, role, rng: @rng, **line)
      @voices << AnalogSynth::LiveVoice.new(midi:, spec:, start:, held:, gain:, role:, rng:, rate: @rate,
                                            drift_cents: @drift, **line)
    end

    # One FM note (AnalogSynth::FmVoice) from a preset.
    def fm(midi, preset, start, held, gain)
      @voices << AnalogSynth::FmVoice.new(midi:, preset:, start:, held:, gain:, rng: @rng, rate: @rate)
    end

    def stop! = @stopping = true

    def run(score, sink, seconds: nil)
      frame = 0
      ending = nil
      loop do
        clock = frame.to_f / @rate
        @inbox.each(clock) { |command| command["stop"] ? stop! : score.command(command, clock) }
        ending ||= clock if @stopping || score.finished?(clock) || (seconds && clock >= seconds)
        @stopped_at ||= clock if @stopping
        score.schedule(self, clock) unless ending
        break if ending && clock - ending > @tail
        break if @stopped_at && clock - @stopped_at > @fade

        sink.write(block(score, clock))
        frame += @block
      end
    end

    def block(score, clock)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      left = Array.new(@block, 0.0)
      right = Array.new(@block, 0.0)
      knobs = score.knobs.step(@block.to_f / @rate, clock)
      @voices.each { |voice| voice.render!(left, right, clock, **shape(score, voice, knobs)) }
      extra = score.respond_to?(:overdub!) ? score.overdub!(left, right, clock, @rate) : nil
      [left, right, extra].compact.each { |channel| fade!(channel, clock) } if @stopped_at
      @voices.reject! { |voice| voice.done?(clock) }
      pcm = if score.respond_to?(:pcm) then score.pcm(left, right, extra, knobs)
            else AnalogSynth.live_pcm(left, right, drive: @drive, scale: @scale)
            end
      account(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      pcm
    end

    # How much of one core the sound costs: seconds spent rendering per second
    # rendered. Past 1.0 the pipe starves and the sound stutters.
    def meter = format("%.2f of a core at %d Hz", @played.zero? ? 0.0 : @spent / @played, @rate)

    private

    # A straight line down from where the stop landed, so the last block ends
    # at silence instead of on whatever sample it was cut at.
    def fade!(channel, clock)
      j = 0
      while j < channel.length
        channel[j] *= (1.0 - ((clock + (j.to_f / @rate) - @stopped_at) / @fade)).clamp(0.0, 1.0)
        j += 1
      end
    end

    # An FM voice bends on the raw knobs; a patch voice takes its role's shape.
    def shape(score, voice, knobs)
      voice.is_a?(AnalogSynth::FmVoice) ? { knobs: } : score.knobs.shape(voice, knobs)
    end

    def account(spent)
      @spent += spent
      @played += @block.to_f / @rate
      LiveSynth.log(meter) if (@played % 60.0) < (@block.to_f / @rate)
    end
  end

  # The chord that plays after the one playing, chosen as it goes, with the
  # kit under it and the whole stream sent out through dilla's pad chain and
  # a dub send.
  class Improviser
    attr_reader :rng, :knobs

    NAMES = DillaImprovisation::PITCH_NAMES

    def initialize(rng:, family: nil, pad: nil)
      @c = LiveSynth.config.fetch("improvise")
      @rng = rng
      fam = family ? @c.fetch("families").fetch(family) { abort "live0: no family #{family}" } : {}
      @pads = fam.fetch("pads", @c["pads"])
      @leads = fam.fetch("leads", @c["leads"])
      @bass = fam.fetch("bass_patch", @c["bass_patch"])
      @moves = @c.fetch("moves").to_h { |row| [row["from"], row["to"]] }
      @beat = 60.0 / (@c["bpm"] + rng.rand(-@c["bpm_spread"].to_f..@c["bpm_spread"].to_f))
      @knobs = Knobs.new(@c.fetch("knobs"), response: @c.fetch("response"), rng:,
                         damping: @c["walk_damping"], pull: @c["walk_pull"])
      @key = @c.fetch("keys").sample(random: rng)
      @state = @c.fetch("start")
      @voicing = []
      @pad = pad ? Patches.name!(pad) : @pads.sample(random: rng)
      @lead = @leads.sample(random: rng)
      @family = family
      @chords_on_pad = 0
      @chords = 0
      @next_at = @c["first_chord_at"]
      @lead_on = false
      @lead_enabled = @c["lead_enabled"]
      @drums = @c["drums"]
      @fade = nil
      @kit = Kit.new(@c, beat: @beat, rng:)
    end

    def describe = "improvising, #{(60.0 / @beat).round} bpm in #{NAMES[@key]} minor#{" on #{@family}" if @family}"

    def finished?(_clock) = false

    # The next chord is written a second ahead of the playhead.
    def schedule(stage, clock)
      chord!(stage) while @next_at < clock + @c["lookahead_seconds"]
    end

    # The kit into the block after the voices; the kick comes back on its own.
    def overdub!(left, right, clock, rate) = @kit.render!(left, right, clock, rate)

    def player_command(rate, dest)
      Dub.command(@c["post"], rate:, beat: @beat, dest:) ||
        abort("live0: improvising leaves through ffmpeg -- install ffmpeg and sox (brew install ffmpeg sox)")
    end

    def pcm(left, right, kick, knobs) = Dub.pcm(left, right, kick, knobs["dub"])

    # What a sentence can change while it plays: a patch, a knob, the drums,
    # the lead, and which engine plays the lead.
    def command(command, clock)
      if command["patch"] then take_patch(command["patch"])
      elsif command["knob"] then LiveSynth::Say.turn!(@knobs, command, clock)
      elsif command["toggle"] == "drums" then drums!(command["on"])
      elsif command["toggle"] == "lead" then lead_switch!(command["on"])
      elsif command["lead"] == "fm" then fm_lead!(command["preset"])
      end
    end

    private

    def take_patch(name)
      return change_pad(name) if Patches.role(name) == :pad

      @lead = name
      lead_switch!(true)
    end

    def drums!(on)
      @drums = on
      LiveSynth.log("drums #{on ? 'in' : 'out'}")
    end

    def lead_switch!(on)
      @lead_enabled = on
      @lead_on = on
      LiveSynth.log(on ? "lead in: #{@lead}" : "lead out")
    end

    def fm_lead!(preset)
      @leads = @c.fetch("fm").keys
      @lead = @leads.include?(preset) ? preset : @leads.sample(random: @rng)
      lead_switch!(true)
    end

    def chord!(stage)
      bars = @rng.rand < @c["two_bar_odds"] ? 2 : 1
      length = bars * 4 * @beat
      degree, quality = @state
      @voicing = DillaImprovisation.nearest_voicing(DillaImprovisation.pitch_classes(@key, degree, quality), @voicing,
                                                    range: Range.new(*@c["voicing_range"]), first: @c["first_voicing"])
      pad = pad_spec
      @voicing.each { |midi| stage.note(midi, pad, @next_at, length - 0.05, @c["pad_gain"], :pad) }
      bass!(stage, (36 + ((@key + degree) % 12)).then { |root| root < 38 ? root + 12 : root }, bars)
      @kit.write!(@next_at, length) if @drums
      lead!(stage, length) if @lead_on
      @chords += 1
      @chords_on_pad += 1
      LiveSynth.log("#{NAMES[(@key + degree) % 12]}#{quality} (#{bars} bar#{'s' if bars > 1}) on #{@pad}" \
                    "#{" + #{@lead}" if @lead_on}")
      @next_at += length
      move!
    end

    # Dilla: the root on the one, then late pushes and a fifth or an octave.
    def bass!(stage, root, bars)
      spec = Patches.spec(@bass)
      late = @c["bass_late_seconds"]
      at = @next_at
      stage.note(root, spec, at + 0.01, 1.3 * @beat, 0.5, :bass)
      stage.note(root, spec, at + (1.5 * @beat) + late, 0.45 * @beat, 0.38, :bass) if @rng.rand < 0.7
      if @rng.rand < 0.5
        stage.note(root + [7, 12, 10].sample(random: @rng), spec, at + (2.5 * @beat) + late, 0.4 * @beat, 0.32, :bass)
      end
      return unless bars == 2

      stage.note(root, spec, at + (4 * @beat) + 0.01, 1.2 * @beat, 0.46, :bass)
      stage.note(root + 7, spec, at + (5.5 * @beat) + late, 0.5 * @beat, 0.34, :bass) if @rng.rand < 0.6
    end

    def lead!(stage, length)
      @c.fetch("fm").key?(@lead) ? fm_phrase!(stage, length) : patch_phrase!(stage, length)
    end

    # FM: wider leaps over three octaves of chord tones, uneven lengths, and
    # each note its own bent spectrum.
    def fm_phrase!(stage, length)
      phrase = @c.fetch("fm_phrase")
      preset = @c.fetch("fm").fetch(@lead).transform_keys(&:to_sym)
      tones = @voicing + @voicing.map { |m| m + 12 } + @voicing.map { |m| m + 24 }
      spot = @next_at + ((@rng.rand < 0.5 ? 0.5 : 1.0) * @beat)
      last = tones.sample(random: @rng)
      reach = phrase["reach"]
      while spot < @next_at + length - 0.4
        last = tones.min_by { |m| (m - last - @rng.rand(-reach..reach)).abs }
        duration = phrase["steps"].sample(random: @rng) * @beat
        if @rng.rand < phrase["odds"]
          stage.fm(last.clamp(*phrase["range"]), preset, spot, duration * phrase["held"], phrase["gain"])
        end
        spot += duration
      end
    end

    # A patch lead: stepwise toward chord tones an octave or two up, swung,
    # with rests. A Model D lead glides in from its last note.
    def patch_phrase!(stage, length)
      tones = @voicing.map { |m| m + 12 } + @voicing.map { |m| m + 24 }
      spot = @next_at + ((@rng.rand < 0.5 ? 0.5 : 1.0) * @beat)
      last = tones.sample(random: @rng)
      spec = Patches.spec(@lead)
      while spot < @next_at + length - 0.4
        last = tones.min_by { |m| (m - last - @rng.rand(-5..5)).abs }
        duration = [0.5, 0.5, 1.0, 1.5].sample(random: @rng) * @beat
        swing = ((spot - @next_at) / (@beat / 2)).round.odd? ? @c["lead_swing_seconds"] : 0.0
        if @rng.rand < @c["lead_odds"]
          note = last.clamp(*@c["lead_range"])
          stage.note(note, spec, spot + swing, duration * 0.9, @c["lead_gain"], :lead, from_midi: @last_lead)
          @last_lead = note
        end
        spot += duration
      end
    end

    def move!
      @state = DillaImprovisation.walk(@moves, @state, @rng)
      change_pad((@pads - [@pad]).sample(random: @rng)) if @chords_on_pad >= @rng.rand(Range.new(*@c["pad_chords"]))
      toggle_lead! if @lead_enabled && @rng.rand < @c["lead_toggle_odds"]
      modulate! if (@chords % @c["modulate_every"]).zero? && @state.first.zero?
    end

    def change_pad(name)
      @fade = [Patches.spec(@pad), 0]
      @pad = name
      @chords_on_pad = 0
      LiveSynth.log("patch -> #{@pad}")
    end

    # The first chords on a new pad play it with the old one's knobs turning
    # into its own, a step a chord.
    def pad_spec
      spec = Patches.spec(@pad)
      steps = LiveSynth.config.dig("automation", "crossfade_chords").to_i
      return spec unless @fade && @fade[1] < steps

      from, done = @fade
      @fade = [from, done + 1]
      AnalogSynth.blend(from, spec, (done + 1).to_f / (steps + 1))
    end

    def toggle_lead!
      @lead_on = !@lead_on
      @lead = @leads.sample(random: @rng) if @lead_on
      LiveSynth.log(@lead_on ? "lead in: #{@lead}" : "lead out")
    end

    def modulate!
      @key = (@key + @c["modulate_by"].sample(random: @rng)) % 12
      @state = [0, %w[m9 m11].sample(random: @rng)]
      LiveSynth.log("modulate -> #{NAMES[@key]} minor")
    end
  end

  # The improviser's drums, written a chord ahead and rendered in the block:
  # the kick and its doubles on a bus of their own, the clap into the music.
  class Kit
    # The clap's noise is its own stream, seeded off the take's, so the drums
    # never shift a draw the harmony makes.
    NOISE_SEED = 0x5eed
    # The clap's band and body into its saturator.
    BAND_GAIN = 1.6
    BODY_GAIN = 0.5
    # A roll is the last beat of the chord: a beat of sixteenths, then half a
    # beat of 32nds, each hit a little harder than the one before.
    ROLL = [[0.0, 4], [0.5, 8]].freeze
    SILENT_BAND = 1e-6

    def initialize(config, beat:, rng:)
      @kick = config.fetch("kick")
      @snare = config.fetch("snare")
      @beat = beat
      @rng = rng
      @noise = Random.new(rng.seed ^ NOISE_SEED)
      @kicks = []
      @snares = []
      @low = 0.0
      @band = 0.0
    end

    def write!(start, length)
      @kicks.concat(kick_hits(start, length))
      @snares.concat(snare_hits(start, length))
    end

    # Adds the clap into left and right; returns the kick for its own channels.
    def render!(left, right, clock, rate)
      span = left.length.to_f / rate
      kicks = @kicks.select { |t, _| t < clock + span && t > clock - @kick["length_seconds"] }
      snares = @snares.select { |t, _| t < clock + span && t > clock - @snare["length_seconds"] }
      kick = Array.new(left.length, 0.0)
      j = 0
      while j < left.length
        now = clock + (j.to_f / rate)
        bus = kick_bus(kicks, now)
        clap!(left, right, j, now, snares)
        kick[j] = Math.tanh(bus * @kick["bus_drive"]) * @kick["bus_gain"] * @kick["level"]
        j += 1
      end
      @kicks.reject! { |t, _| t < clock - @kick["length_seconds"] }
      @snares.reject! { |t, _| t < clock - @snare["length_seconds"] }
      kick
    end

    private

    def kick_hits(start, length)
      hits = []
      (length / @beat).round.times do |b|
        t = start + (b * @beat)
        hits << [t, 1.0]
        @kick["ghosts"].each { |odds, at, gain| hits << [t + (@beat * at), gain] if @rng.rand < odds }
      end
      roll!(hits, start + length - @beat) if @rng.rand < @kick["roll_odds"]
      hits.uniq { |t, _| (t * 1000).round }
    end

    def roll!(hits, from)
      ROLL.zip(@kick["roll_gains"]).each do |(offset, division), (gain, rise)|
        4.times { |i| hits << [from + (@beat * offset) + (i * @beat / division), gain + (i * rise)] }
      end
    end

    def snare_hits(start, length)
      hits = []
      (length / @beat).round.times do |b|
        t = start + (b * @beat)
        hits << [t + @snare["late_seconds"], 1.0] if b.odd?
        @snare["ghosts"].each do |ghost|
          next if ghost["even_beats"] && !b.even?

          hits << [t + (@beat * ghost["at"]), ghost["gain"]] if @rng.rand < ghost["odds"]
        end
      end
      hits
    end

    # Summed hit by hit, in the order they were written.
    def kick_bus(kicks, now)
      bus = 0.0
      kicks.each do |t, gain|
        tk = now - t
        next if tk.negative? || tk > @kick["length_seconds"]

        bus += kick_sample(tk) * gain
      end
      bus
    end

    def kick_sample(tk)
      drop = @kick["drop_seconds"]
      phase = 2 * Math::PI * ((@kick["base_hz"] * tk) + (@kick["drop_hz"] * drop * (1.0 - Math.exp(-tk / drop))))
      click = tk < @kick["click_seconds"] ? (1.0 - (tk / @kick["click_seconds"])) * @kick["click"] : 0.0
      (Math.sin(phase) * Math.exp(-tk / @kick["decay_seconds"])) + click
    end

    # Three noise bursts a few milliseconds apart and a tail, through a
    # state-variable band-pass, over a short sine body, saturated.
    def clap!(left, right, j, now, snares)
      s = @snare
      clap = 0.0
      body = 0.0
      snares.each do |t, gain|
        ts = now - t
        next if ts.negative? || ts > s["length_seconds"]

        bursts = (0..2).sum { |k| (d = ts - (k * s["burst_gap_seconds"])).negative? ? 0.0 : Math.exp(-d / s["burst_seconds"]) }
        clap += (bursts + (Math.exp(-ts / s["tail_seconds"]) * s["tail_gain"])) * gain
        body += Math.sin(2 * Math::PI * s["body_hz"] * ts) * Math.exp(-ts / s["body_seconds"]) * gain
      end
      return if clap.zero? && body.zero? && @band.abs < SILENT_BAND

      x = clap * ((@noise.rand * 2.0) - 1.0)
      @low += s["filter_f"] * @band
      @band += s["filter_f"] * (x - @low - (s["filter_damping"] * @band))
      snare = Math.tanh(((@band * BAND_GAIN) + (body * BODY_GAIN)) * s["drive"]) * s["level"]
      left[j] += snare * s["pan"]
      right[j] += snare * (1.0 - s["pan"])
    end
  end

  # The way out for the improviser: ffmpeg splits the music into dilla's pad
  # chain and a dub send and mixes the kick back in dry, then the player.
  # Six channels go in -- the music, the music at the dub knob's level for the
  # send, and the kick -- so turning the dub knob needs no restart.
  module Dub
    SCALE = 26_000
    DRIVE = 1.4

    module_function

    def graph(post, beat)
      chain = warm_dilla_pad_synth_filters(**post.fetch("chain").transform_keys(&:to_sym)).compact.join(",")
      send = post.fetch("dub").gsub(/<(\d+)>/) { (beat * Regexp.last_match(1).to_i).round.to_s }
      "[0:a]pan=stereo|c0=c0|c1=c1[dry];[0:a]pan=stereo|c0=c2|c1=c3[wet];[0:a]pan=stereo|c0=c4|c1=c5[k];" \
        "[dry]#{chain}[d];[wet]#{send}[w];[d][w][k]amix=inputs=3:weights=1 1 1:normalize=0,alimiter=limit=#{post['limit']}"
    end

    def command(post, rate:, beat:, dest: nil)
      LiveSynth.through_ffmpeg(channels: 6, filter: ["-filter_complex", graph(post, beat)], rate:, dest:)
    end

    # The music through the tanh master, the same again scaled for the send,
    # and the kick, already saturated on its bus, as it is.
    def pcm(left, right, kick, dub)
      out = Array.new(left.length * 6)
      i = 0
      while i < left.length
        l = (Math.tanh(left[i] * DRIVE) * SCALE).round
        r = (Math.tanh(right[i] * DRIVE) * SCALE).round
        k = (kick[i] * SCALE).round
        out[i * 6, 6] = [l, r, (l * dub).round, (r * dub).round, k, k]
        i += 1
      end
      out.pack("s<*")
    end
  end

  # A named progression, looped: written voicings from data/live.yml, or any
  # chord list voiced nearest-note. An entry with a `walk` opens on its chords
  # and then chooses the rest as it goes; one with a `dfam` plays a DFAM under
  # it; one with a `master` leaves through that console. MASTER's main sound
  # is two of these, moog_dfam and moog_improv.
  class Progression
    attr_reader :rng, :knobs

    # loops: how many times round; nil takes the entry's own, 0 goes round
    # until stopped.
    def initialize(name, rng:, pads: nil, family: nil, loops: nil)
      table = LiveSynth.config.fetch("progressions")
      defaults = table.fetch("soul_jazz_six").except("chords")
      @name = name
      @p = defaults.merge(resolve(table, table.fetch(name) { { "names" => catalogue(name) } }))
      @chords = @p["chords"] || voiced(@p.fetch("names"))
      @pads = pads&.map { |pad| Patches.name!(pad) } ||
              (family && LiveSynth.config.dig("improvise", "families", family, "pads")) || @p["pads"]
      @rng = rng
      @loops = (loops || @p["loops"]).then { |n| n.to_i.positive? ? n.to_i : nil }
      @knobs = Knobs.new(@p.fetch("knobs"), response: @p.fetch("response"), rng:)
      @walk = @p["walk"] && Walk.new(@p["walk"], opening: @chords)
      @dfam = @p["dfam"] && Dfam.new(@p["dfam"], step: @p["bar_seconds"] / @p["dfam"]["steps_per_bar"], seed: rng.seed)
      @count = 0
      @at = 0.0
      @override = nil
    end

    def describe
      "#{@name}, #{@walk ? 'walking from' : ''} #{@chords.size} chords on #{@pads.join(' -> ')}" \
        "#{' over a DFAM' if @dfam}".squeeze(" ")
    end

    def overdub!(left, right, clock, rate)
      @dfam&.render!(left, right, clock, rate)
      nil
    end

    # The console the entry names, or nil for the plain tanh master.
    def player_command(rate, dest)
      return nil unless @p["master"]

      chain = @p["master"].map { |stage| LiveSynth.console_stage(stage) }.join(",")
      LiveSynth.through_ffmpeg(channels: 2, filter: ["-af", chain], rate:, dest:) ||
        abort("live0: #{@name} leaves through ffmpeg -- install ffmpeg and sox (brew install ffmpeg sox)")
    end

    def finished?(clock) = @loops && !@walk && @count >= @loops * @chords.size && clock >= @at

    def schedule(stage, clock)
      chord!(stage) while @at < clock + 1.0 && !(@loops && !@walk && @count >= @loops * @chords.size)
    end

    def command(command, clock)
      if command["patch"]
        @override = [Patches.spec(pad_name), Patches.name!(command["patch"]), 0]
        LiveSynth.log("pad -> #{command['patch']}")
      elsif command["knob"]
        LiveSynth::Say.turn!(@knobs, command, clock)
      end
    end

    private

    def pad_name = @override ? @override[1] : @pads[(@count / @p["pad_every"]) % @pads.size]

    def bass_name
      basses = @p["basses"] or return @p["bass_patch"]

      basses[(@count / @p["bass_every"]) % basses.size]
    end

    # Each note seeded on its pitch and its start, so a progression played
    # twice is the same take.
    def note(stage, midi, spec, start, held, gain, role)
      stage.note(midi, spec, start, held, gain, role, rng: Random.new((midi * 7) + (start * 10).to_i))
    end

    def chord!(stage)
      chord = @walk ? @walk.next(@count, @rng) : @chords[@count % @chords.size]
      pad = pad_spec
      chord["tones"].each { |midi| note(stage, midi, pad, @at, @p["bar_seconds"] - 0.1, @p["pad_gain"], :pad) }
      bass = Patches.spec(bass_name)
      @p["bass_hits"].each { |offset, length, gain| note(stage, chord["bass"], bass, @at + offset, length, gain, :bass) }
      LiveSynth.log("#{chord['name']} on #{pad_name}#{", bass #{bass_name}" if @p['basses']}")
      arpeggio!(stage, chord["tones"]) if @p["arp"] && @rng.rand < @p["arp"]["odds"]
      @count += 1
      @at += @p["bar_seconds"]
    end

    # Sixteenths across the bar an octave over the voicing: up, down,
    # up-and-down, or shuffled.
    def arpeggio!(stage, tones)
      arp = @p["arp"]
      patch = arp["patches"].sample(random: @rng)
      notes = tones.map { |m| m + arp["octave"] }
      order = [notes, notes.reverse, notes + notes.reverse[1..-2], notes.shuffle(random: @rng)].sample(random: @rng)
      step = @p["bar_seconds"] / arp["steps"]
      spec = Patches.spec(patch)
      arp["steps"].times { |k| note(stage, order[k % order.size], spec, @at + (k * step), step * arp["held"], arp["gain"], :pad) }
      LiveSynth.log("  arp on #{patch}")
    end

    def pad_spec
      spec = Patches.spec(pad_name)
      return spec unless @override && @override[2] < LiveSynth.config.dig("automation", "crossfade_chords").to_i

      from, name, done = @override
      steps = LiveSynth.config.dig("automation", "crossfade_chords").to_i
      @override = [from, name, done + 1]
      AnalogSynth.blend(from, spec, (done + 1).to_f / (steps + 1))
    end

    def catalogue(name) = CHORD_PROGRESSIONS[name.to_sym] || abort("live0: no progression #{name}")

    # An entry `from:` another is that one with its own keys laid over it,
    # nested tables merged key by key, as far back as the chain goes.
    def resolve(table, entry)
      return entry unless entry["from"]

      deep_merge(resolve(table, table.fetch(entry["from"])), entry.except("from"))
    end

    def deep_merge(base, over)
      base.merge(over) { |_, a, b| a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge(a, b) : b }
    end

    # Named chords to written ones: tones nearest the chord before, the root
    # an octave or two under them for the bass.
    def voiced(names)
      previous = []
      names.filter_map do |name|
        chord = resolve_pad_chord_symbol(name) or next
        midis = chord[:hz].map { |hz| (69 + (12 * Math.log2(hz / 440.0))).round }
        tones = DillaImprovisation.nearest_voicing(midis.map { |m| m % 12 }, previous, range: 48..76,
                                                   first: [55, 60, 63, 67, 70])
        previous = tones
        root = midis.first % 12
        { "name" => name, "bass" => 36 + root, "tones" => tones }
      end
    end
  end

  # The chords the main sound improvises: the opening chords as written, then
  # a walk over improvise.moves, each chord four rootless tones voiced nearest
  # the last, the key moving now and then.
  class Walk
    NAMES = DillaImprovisation::PITCH_NAMES

    def initialize(config, opening:)
      @c = config
      @opening = opening
      @moves = LiveSynth.config.dig("improvise", "moves").to_h { |row| [row["from"], row["to"]] }
      @key = config["key"]
      @state = config["start"]
      @voicing = []
    end

    def next(count, rng)
      return (@opening[count].tap { |chord| @voicing = chord["tones"] }) if count < @opening.size

      degree, quality = @state
      tones = DillaImprovisation.pitch_classes(@key, degree, quality).drop(1)
      @voicing = DillaImprovisation.nearest_voicing(tones, @voicing, range: Range.new(*@c["voicing_range"]), first: @voicing)
      chord = { "name" => "#{NAMES[(@key + degree) % 12]}#{quality}", "bass" => 36 + ((@key + degree) % 12), "tones" => @voicing }
      @state = DillaImprovisation.walk(@moves, @state, rng)
      modulate!(rng) if (count % @c["modulate_every"]).zero? && @state.first.zero?
      chord
    end

    private

    def modulate!(rng)
      @key = (@key + @c["modulate_by"].sample(random: rng)) % 12
      @state = [0, %w[m9 m11].sample(random: rng)]
      LiveSynth.log("modulate -> #{NAMES[@key]} minor")
    end
  end

  # The DFAM under the main sound: an 8-step sequencer in sixteenths of the
  # bar, sequenced a block ahead, each hit its own two oscillators, noise,
  # ladder and decays; improvising, it gains accents, a five-step sequence
  # against the eight, and a kick. The entry's `dfam` carries every number,
  # and the arithmetic below is the reference scripts', in their order.
  class Dfam
    STEPS = DfamEngine::STEPS
    # The mutation draws and the noise are streams of their own, seeded off
    # the take's, so neither moves the other.
    NOISE_SEED = 0xdfa
    Hit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)

    def initialize(config, step:, seed:)
      @c = config
      @step_seconds = step
      @pattern = DfamEngine::DEFAULT_PATTERN.transform_values(&:dup)
      @mutate = Random.new(seed)
      @noise = Random.new(seed ^ NOISE_SEED)
      @hits = []
      @kicks = []
      @next = 0.0
      @step = 0
    end

    def render!(left, right, clock, rate)
      sequence!(clock + (left.length.to_f / rate), rate)
      vcf = knob("vcf_decay", clock)
      vca = knob("vca_decay", clock)
      top = knob("cutoff", clock)
      @hits.each { |hit| sound!(hit, left, right, clock, rate, vcf:, vca:, top:) }
      @hits.reject! { |hit| clock - hit.start > vca * @c["life_decays"] }
      kick!(left, right, clock, rate) if @c["kick"]
    end

    private

    def sequence!(until_time, rate)
      while @next < until_time
        step = @step % STEPS
        velocity = @pattern[:velocity][step] / 100.0
        velocity *= @c["accent"][step] if @c["accent"]
        @hits << hit(@next, @pattern[:pitch][step], velocity, pan(step), rate) if velocity.positive?
        second!(rate) if @c["second"]
        @kicks << @next if @c["kick"] && (@step % @c["kick"]["every"]).zero?
        @step += 1
        mutate! if (@step % @c["mutate_every"]).zero?
        @next += @step_seconds
      end
    end

    def hit(start, pitch, velocity, pan, rate)
      Hit.new(start, @c["base_hz"] * (2.0**(pitch / 100.0 * @c["octaves"])), velocity, 0.0, 0.0,
              AnalogSynth::Ladder.new(rate:), pan)
    end

    def pan(step)
      centre, swing = @c["pan"]
      centre + (swing * (step % 2))
    end

    # The five-step page, a hair behind the eight, quieter, panned wide.
    def second!(rate)
      s = @c["second"]
      b = @step % s["pitch"].size
      return unless s["velocity"][b].positive?

      @hits << hit(@next + s["late_seconds"], s["pitch"][b], s["velocity"][b] / 100.0 * s["gain"], b.even? ? s["pan"][0] : s["pan"][1], rate)
    end

    # One step moves: its pitch by up to pitch_reach, and its velocity by up
    # to velocity_reach, or to silence.
    def mutate!
      m = @c["mutate"]
      k = @mutate.rand(STEPS)
      @pattern[:pitch][k] = (@pattern[:pitch][k] + @mutate.rand(-m["pitch_reach"]..m["pitch_reach"])).clamp(*m["pitch_range"])
      @pattern[:velocity][k] = if @mutate.rand < m["mute_odds"] then 0
                               else (@pattern[:velocity][k] + @mutate.rand(-m["velocity_reach"]..m["velocity_reach"])).clamp(*m["velocity_range"])
                               end
    end

    def knob(name, clock)
      k = @c.fetch("knobs").fetch(name)
      k["floor"] + (k["span"] * (0.5 + (0.5 * Math.sin((2 * Math::PI * clock / k["sine_seconds"]) + k["phase"]))))
    end

    def sound!(hit, left, right, clock, rate, vcf:, vca:, top:)
      c = @c
      j = 0
      while j < left.length
        tt = clock + (j.to_f / rate) - hit.start
        if tt >= 0
          pitch_env = 1.0 + (c["pitch_env"]["depth"] * Math.exp(-tt / c["pitch_env"]["seconds"]))
          hit.ph1 = (hit.ph1 + (hit.f0 * pitch_env / rate)) % 1.0
          tri = AnalogSynth.wave(:triangle, hit.ph1)
          hit.ph2 = (hit.ph2 + (hit.f0 * c["vco2_ratio"] * pitch_env * (1.0 + (c["fm"] * tri)) / rate)) % 1.0
          square = hit.ph2 < 0.5 ? 1.0 : -1.0
          mix = (c["mix"]["triangle"] * tri) + (c["mix"]["square"] * square) + (c["mix"]["noise"] * ((@noise.rand * 2.0) - 1.0))
          cut = c["cutoff_floor"] + (top * Math.exp(-tt / vcf))
          out = hit.ladder.process(mix, cut, c["resonance"]) * hit.vel * Math.exp(-tt / vca) * c["level"]
          left[j] += out * hit.pan
          right[j] += out * (1.0 - hit.pan)
        end
        j += 1
      end
    end

    # The kick, summed from every hit still sounding, into tanh, into both
    # channels of the music.
    def kick!(left, right, clock, rate)
      k = @c["kick"]
      j = 0
      while j < left.length
        now = clock + (j.to_f / rate)
        bus = 0.0
        @kicks.each do |t|
          tk = now - t
          next if tk.negative? || tk > k["length_seconds"]

          bus += Math.sin(2 * Math::PI * ((k["base_hz"] * tk) + (k["drop_hz"] * k["drop_seconds"] * (1.0 - Math.exp(-tk / k["drop_seconds"]))))) * Math.exp(-tk / k["decay_seconds"])
          bus += (tk < k["click_seconds"] ? (1.0 - (tk / k["click_seconds"])) * k["click"] : 0.0)
        end
        level = Math.tanh(bus * k["drive"]) * k["level"]
        left[j] += level
        right[j] += level
        j += 1
      end
      @kicks.reject! { |t| clock - t > k["length_seconds"] }
    end
  end

  # One patch playing its own phrase: the panel's demo for a Model D patch, a
  # line for its part otherwise. A legato patch plays it as one gliding voice.
  class Demo
    attr_reader :rng, :knobs

    # The patch as written: a knob at rest leaves cutoff and resonance alone,
    # and asking still opens or closes it.
    RESPONSE = %w[pad bass lead].to_h { |role| [role, { "cutoff" => [0.5, 1.0], "resonance" => [0.0, nil] }] }.freeze

    def initialize(name, rng:)
      @name = name
      @spec = Patches.spec(name)
      @demo = Patches.demo(name)
      @role = Patches.role(name)
      @rng = rng
      @knobs = Knobs.new({}, response: RESPONSE, rng:)
      @done = false
    end

    def describe = "#{@name}, #{@demo['notes'].size} steps"

    def length = @demo["notes"].size * @demo["step"]

    def finished?(clock) = clock >= length

    def command(command, clock)
      LiveSynth::Say.turn!(@knobs, command, clock) if command["knob"]
    end

    def schedule(stage, _clock)
      return if @done

      @done = true
      @spec[:legato] ? line!(stage) : steps!(stage)
    end

    private

    def gain = @demo.fetch("gain", { pad: 0.22, bass: 0.55, lead: 0.3 }.fetch(@role))

    def steps!(stage)
      @demo["notes"].each_with_index do |step, index|
        Array(step).each do |note|
          stage.note(Say.note_midi(note), @spec, index * @demo["step"], @demo["step"] * @demo["gate"], gain, @role)
        end
      end
    end

    def line!(stage)
      notes = @demo["notes"].map { |note| Say.note_midi(note) }
      path = notes.each_with_index.drop(1).map { |midi, index| [index * @demo["step"], midi] }
      stage.note(notes.first, @spec, 0.0, length, gain, @role, path:)
    end
  end

  # The player's record and its inbox, in a directory both the player and the
  # commands that steer it can find without being told.
  module Session
    STOP_WAIT_SECONDS = 5.0

    module_function

    def home = ENV.fetch("DILLA_LIVE_DIR") { File.join(Dir.tmpdir, "dilla-live-#{Process.uid}") }

    def record_file = File.join(home, "player.json")

    def inbox_file = File.join(home, "inbox.jsonl")

    def log_file = File.join(home, "player.log")

    # The playing record, or nil. A record whose process is gone is removed.
    def playing
      record = File.file?(record_file) && JSON.parse(File.read(record_file))
      return nil unless record
      return record if alive?(record["pid"])

      FileUtils.rm_f(record_file)
      nil
    rescue JSON::ParserError
      nil
    end

    def status
      record = playing
      record ? "playing #{record['what']} (pid #{record['pid']}, since #{record['since']})" : "nothing is playing"
    end

    # One player at a time: whatever was playing stops first. A player that
    # reads no inbox is recorded as one, so a sentence meant to steer it is
    # told so rather than dropped.
    def claim!(what, steerable: true)
      stop! unless playing&.fetch("pid") == Process.pid
      FileUtils.mkdir_p(home)
      File.write(inbox_file, "")
      File.write(record_file, JSON.generate("pid" => Process.pid, "what" => what, "steerable" => steerable,
                                            "since" => Time.now.strftime("%H:%M:%S")))
    end

    def release!
      FileUtils.rm_f(record_file) if playing&.fetch("pid") == Process.pid
    end

    def stop!
      record = playing or return "nothing is playing"

      pid = record["pid"]
      Process.kill("TERM", pid)
      deadline = Time.now + STOP_WAIT_SECONDS
      sleep 0.05 while alive?(pid) && Time.now < deadline
      alive?(pid) ? kill_group(pid) : end_group(pid)
      FileUtils.rm_f(record_file)
      "stopped #{record['what']} (pid #{pid})"
    rescue Errno::ESRCH
      FileUtils.rm_f(record_file)
      "stopped"
    end

    # A player that ignored TERM goes with everything it started: a spawned
    # player leads its own process group, and its ffmpeg and sox are in it.
    def kill_group(pid)
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH, Errno::EPERM
      Process.kill("KILL", pid)
    end

    # The player gone, the ffmpeg and sox it started would play out their
    # buffers for seconds more; a stop is a stop, so they go too. A player run
    # from a terminal leads no group of its own and has nothing left here.
    def end_group(pid)
      Process.kill("TERM", -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def post!(command)
      record = playing or return "nothing is playing"
      return "#{record['what']} plays as frozen and turns its own knobs; stop it, or ask for another sound to steer" if record["steerable"] == false

      File.open(inbox_file, "a") { |file| file.puts(JSON.generate(command.compact)) }
      "sent #{command.compact.map { |key, value| "#{key}=#{value}" }.join(' ')} to pid #{record['pid']}"
    end

    # A player of its own, detached, so the sentence that started it returns
    # at once and the sound outlives it.
    def spawn!(args)
      stop!
      FileUtils.mkdir_p(home)
      pid = Process.spawn(RbConfig.ruby, ENGINE, "live", *args, chdir: Livesets::D, in: File::NULL,
                                                                out: [log_file, "a"], err: [:child, :out], pgroup: true)
      Process.detach(pid)
      pid
    end

    def alive?(pid)
      Process.kill(0, pid.to_i)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # Commands appended while the player runs, read a few times a second of
    # sound so a knob asked for moves within the block after.
    class Inbox
      POLL_SECONDS = 0.25

      def initialize
        @offset = File.size?(Session.inbox_file) || 0
        @next = 0.0
      end

      def each(clock)
        return if clock < @next

        @next = clock + POLL_SECONDS
        return unless File.file?(Session.inbox_file)

        File.open(Session.inbox_file) do |file|
          file.seek(@offset)
          file.each_line do |line|
            command = JSON.parse(line)
          rescue JSON::ParserError
            next
          else
            yield command
          end
          @offset = file.pos
        end
      end
    end
  end

  # A sentence to a live command. MASTER hands over what the operator said;
  # the instrument's vocabulary -- its patches, progressions, knobs -- lives
  # here with the instrument.
  module Say
    STOP = /\A\s*(?:stop|silence|quiet|enough|shh+)\b|\b(?:stop|end|kill)\s+(?:the\s+)?(?:music|playing|synth\w*|improvi\w*|jam|sound|it|that)\b/.freeze
    MORPH = /\b(?:morph|switch|change|fade|move|turn|go)\w*\s+(?:it\s+|over\s+|across\s+|slowly\s+)?(?:to|into)\b/.freeze
    # The improviser with drums, dub and FM is asked for by those parts.
    JAM = /\b(?:drums?|dub|fm|industrial|jam\w*|kick|snare|beat)\b/.freeze
    MODEL_D = /\b(?:model\s*d|minimoog)\b/.freeze
    PROGRESSION = /\bchords?\b|\bprogressions?\b|\bchanges\b/.freeze
    KNOBS = {
      "cutoff" => /\b(?:filter|cutoff|cut-off|brighter|darker|brightness)\b/,
      "resonance" => /\b(?:resonan\w*|emphasis|squelch\w*|peak)\b/,
      "detune" => /\b(?:detun\w*|chorus\w*|wider|width|spread)\b/,
      "contour" => /\b(?:contour|envelope)\b/,
      "dub" => /\b(?:dub|echo|delay|space)\b/,
    }.freeze
    # Parts that come and go by name: "drums off", "bring the lead in".
    TOGGLES = { "drums" => /\b(?:drums?|kit|kick|snare|beat)\b/, "lead" => /\b(?:lead|melody|solo)\b/ }.freeze
    ON = /\b(?:on|in|back|bring|start|add)\b/.freeze
    OFF = /\b(?:off|out|mute|kill|drop|stop|without|remove|lose)\b/.freeze
    FM_LEAD = /\bfm\b/.freeze
    UP = /\b(?:open\w*|up|raise|more|brighter|increase|wider|boost|lift|push)\b/.freeze
    DOWN = /\b(?:clos\w*|down|lower|less|darker|decrease|narrow\w*|cut|reduce|shut|tame)\b/.freeze
    ALL_THE_WAY = /\b(?:all\s+the\s+way|fully|completely|max\w*)\b/.freeze
    FAMILIES = %w[moog prophet rhodes].freeze
    NOTE = /\A([A-G]#?)(-?\d)\z/.freeze

    module_function

    def call(text)
      words = text.downcase
      steer = steering(words)
      return Session.post!(steer) if steer
      return Session.stop! if words.match?(STOP)

      knob = KNOBS.find { |_, pattern| words.match?(pattern) }&.first
      return Session.post!(knob_command(knob, words)) if knob && !play?(words)
      return morph(words) if words.match?(MORPH)

      args = play_args(words)
      "#{args.join(' ')} (pid #{Session.spawn!(args)}, log #{Session.log_file})"
    end

    def play?(words) = words.match?(/\bplay\b/) && !words.match?(MORPH)

    # "fm lead [preset]", or a part switched on or off -- a command for the
    # player, or nil when the sentence asks for neither.
    def steering(words)
      if words.match?(FM_LEAD)
        preset = LiveSynth.config.dig("improvise", "fm").keys.find { |name| words.match?(/\b#{name}\b/) }
        return { "lead" => "fm", "preset" => preset }
      end
      part = TOGGLES.find { |_, pattern| words.match?(pattern) }&.first
      return nil unless part && (words.match?(ON) || words.match?(OFF))

      { "toggle" => part, "on" => !words.match?(OFF) }
    end

    def morph(words)
      patch = Patches.find(words).last || family_default(words)
      return "no patch named in \"#{words}\"" unless patch

      command = { "patch" => patch, "seconds" => seconds(words) }
      Session.playing ? Session.post!(command) : "improvise pad=#{patch} (pid #{Session.spawn!(['improvise', "pad=#{patch}"])})"
    end

    # Nothing named plays the main sound, which is soul_jazz_six's moog
    # patches over a DFAM, so "moog patches" asks for it too. A named
    # progression, patch, or other family, or one of the improviser's parts,
    # asks for that instead.
    def play_args(words)
      patches = Patches.find(words)
      family = FAMILIES.find { |name| words.match?(/\b#{name}\b/) }
      progression = progression_in(words)
      return ["progression", progression, *with(patches, family)] if progression
      return ["improvise", *(family ? ["family=#{family}"] : []), *(patches.any? ? ["pad=#{patches.first}"] : [])] if words.match?(JAM)
      return patches.size > 1 || words.match?(PROGRESSION) ? ["progression", "soul_jazz_six", *with(patches, nil)] : ["patch", patches.first] if patches.any?
      return %w[improvise family=moog] if words.match?(MODEL_D)
      return ["progression", "soul_jazz_six", "family=#{family}"] if family && family != "moog"

      ["default"]
    end

    def with(patches, family)
      return ["pads=#{patches.join(',')}"] if patches.any?

      family ? ["family=#{family}"] : []
    end

    def family_default(words)
      family = FAMILIES.find { |name| words.match?(/\b#{name}\b/) } or return nil
      LiveSynth.config.dig("improvise", "families", family, "pads").first
    end

    def progression_in(words)
      names = LiveSynth.config.fetch("progressions").keys + CHORD_PROGRESSIONS.keys.map(&:to_s)
      names.sort_by { |name| -name.length }.find { |name| words.match?(/\b#{Regexp.escape(name)}\b|\b#{Regexp.escape(name.tr('_', ' '))}\b/) }
    end

    def knob_command(knob, words)
      step = LiveSynth.config.dig("automation", "step")
      down = words.match?(DOWN) && !words.match?(/\b(?:up|open\w*|brighter|more)\b/)
      command = { "knob" => knob, "seconds" => seconds(words) }
      return command.merge("to" => down ? 0.0 : 1.0) if words.match?(ALL_THE_WAY)
      return command.merge("to" => 0.0) if words.match?(/\b(?:no|dry)\b/)

      command.merge("amount" => format("%+.2f", down ? -step : step))
    end

    def seconds(words)
      speeds = LiveSynth.config.dig("automation", "speeds")
      speeds.find { |word, _| words.match?(/\b#{word}\b/) }&.last || LiveSynth.config.dig("automation", "default_seconds")
    end

    # A knob command, from the inbox or the command line, applied at clock.
    def turn!(knobs, command, clock)
      amount = command["amount"].to_s
      seconds = (command["seconds"] || LiveSynth.config.dig("automation", "default_seconds")).to_f
      if command.key?("to") || !amount.match?(/\A[+-]/)
        knobs.turn(command["knob"], clock:, seconds:, to: (command["to"] || amount).to_f)
      else
        knobs.turn(command["knob"], clock:, seconds:, by: amount.to_f)
      end
      LiveSynth.log("knob #{command['knob']} #{command['to'] || amount} over #{seconds.round(1)}s")
    rescue ArgumentError => e
      LiveSynth.log(e.message)
    end

    def note_midi(name)
      match = name.to_s.match(NOTE) or raise ArgumentError, "not a note: #{name}"
      Livesets::NOTE_PC.fetch(match[1][0]) + (match[1].length == 2 ? 1 : 0) + ((match[2].to_i + 1) * 12)
    end
  end
end
