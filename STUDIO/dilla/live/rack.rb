# frozen_string_literal: true

# The rack the sets are patched into.
#
# Three livesets play this room: ambient_pads, sampled_based_beats and
# chord_based_beats. What they share is the room -- the console, the crate, the
# clock and the journal -- and what differs is the arrangement, which is what a
# set is. Written the other way, as three standalone scripts, the console would
# have drifted between them within a week and the same beat would have sounded
# like three rooms.
#
# Sonitex STX-1260 and Nasty VCS, as chains rather than as plugins. Multiple
# instances deliberately: one instance is a colour and three are a sound. The
# 1260 is the 12-bit sampler lineage -- bit reduction, a hard band limit, drive
# into that limit. VCS is a summing colour, applied wherever things are added,
# which is what a console does and why summed material glues.
require "fileutils"
require "json"
require "time"
require "shellwords"

module Rack
  D = File.expand_path("..", __dir__)
  FF = "/opt/homebrew/bin/ffmpeg"
  FFPLAY = "/opt/homebrew/bin/ffplay"
  FFPROBE = "/opt/homebrew/bin/ffprobe"
  JOURNAL = File.join(D, "project", "liveset.jsonl")
  WORTH = File.join(D, "project", "sample_worth.json")

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
  # seed lands on a different record tomorrow. A number that names a pass has to
  # name it next week too.
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
  # appears to turn.
  # aphaser is not unity: in_gain and out_gain multiply, so 0.6 x 0.72 is a
  # 7dB cut per instance and three instances threw away 22dB before the limiter
  # ever saw the signal. Makeup here rather than at the master, so each console
  # stage stays level-neutral and the weights above mean what they say.
  def vcs(depth:, smear:)
    "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
      "volume=1.9," \
      "aecho=0.9:0.25:#{smear.round}:0.08"
  end

  # The kit is one-shots or it is arithmetic.
  #
  # drunk_kit synthesises its four hits from a sine and two noise bursts, and
  # that is a drum machine, not a record. The lineage this room is after ran
  # sampled hardware -- one-shots taken off real machines and run to tape --
  # and the whole reason the drums glue is that they were recorded before they
  # were played. samples/drums/ holds several such kits already and no set has
  # ever reached for one.
  #
  # A directory qualifies if it has all four roles. Naming a kit that does not
  # resolve aborts rather than falling back: silently rendering the synthesised
  # kit under a sampled kit's name puts a lie in the journal, and the journal is
  # what makes a pass recallable.
  KIT_ROLES = %w[kick snare ghost hat].freeze

  def kit_dir
    want = ENV.fetch("LIVE_KIT", "").to_s
    return nil if want.empty? || want == "synth"

    dir = File.join(D, "samples", "drums", want)
    missing = KIT_ROLES.reject { |r| File.file?(File.join(dir, "#{r}.wav")) }
    abort "kit #{want}: no #{missing.join(', ')}" unless missing.empty?

    dir
  end

  # Every pass is written down before it is heard. The rig was ephemeral once and
  # a swept scratchpad took the takes with it -- the same defect that lost the
  # crate: provenance living somewhere more fragile than what it describes.
  #
  # kit is merged rather than passed by each set: a pass replayed with a
  # different kit is a different take wearing the same seed, so the name has to
  # be in the line whether or not the set thought to write it. It is set by
  # drunk_kit, so the pad set -- which has no drums -- records none.
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
  # as a crate. The journal already records what played and when, so it is also the
  # play history -- one file, two jobs, no second source to drift.
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
  # thin the arrangement is against the record's own habit. chop ranks candidates
  # by seam cost, which finds seamless regions; this asks whether they are worth
  # hearing, which is a different question and the one that was never asked.
  #
  # Verified independent of level: Pearson(sw, rms_db) = 0.082 across 122 unique
  # racks, so this is not loudness wearing a new name.
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
  # whole loop divided by however many bars it holds. The rack's loops.json only
  # ever carries the last chop's entries, so the length is measured off the file
  # instead -- ffprobe is the one reader that cannot go stale.
  #
  # And the drag moves the tempo with the pitch. asetrate slows the sample, so a
  # bar that was T seconds is now T/drag, and a kit built on the undragged figure
  # would run ahead of the record all night. This is what warping the drums to the
  # flow of the sample actually means.
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

  # One synthesised one-shot, split and dropped at each of its hit times.
  #
  # aevalsrc is avoided on long durations -- ruinously slow. One-shots are
  # synthesised once, short, and placed with adelay, which costs nothing.
  def place(idx, label, filt, hits)
    out = ["[#{idx}:a]#{filt}[#{label}_s]"]
    out << "[#{label}_s]asplit=#{hits.size}#{(0...hits.size).map { |k| "[#{label}x#{k}]" }.join}"
    # adelay refuses a negative delay, and the jitter that makes the drums drunk
    # can push a hit on the one below zero. Clamped here rather than at every call
    # site, so no future pattern can reintroduce it: the graph either builds or it
    # does not, and an intermittent failure is the worst kind.
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
  # with either. Uniform swing sounds like a preset; this does not.
  # Appends its own sources and returns the index of the last one, which is the
  # crackle. On the synthesised kit the hats and the record noise are the same
  # long pink generator, read twice. That is not a saving, it is the sound --
  # 0.006 amplitude pink through a 7.2 kHz high-pass is the hat, and the same
  # noise unfiltered is the surface the whole thing sits on, so they share a
  # grain no two generators would. ffmpeg splits the input for the second reader
  # on its own. A sampled kit brings its own hat, so there the crackle is the
  # only generator and stands alone.
  def drunk_kit(n, inputs, graph, beat:, bar:, step:, sxt:, total:)
    dir = kit_dir
    @kit_used = dir ? File.basename(dir) : "synth"
    # anoisesrc seeds itself from the clock unless told otherwise, so without
    # these the snare, the ghost and the crackle are different noise every run
    # and a replayed seed comes back with every number identical and the audio
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
      # Almost nothing on the way in. A synthesised hit needs a filter to become
      # a drum -- that is what the band-passes below are doing -- and a recorded
      # one already is one. The shaping a sampled kit wants happens after the
      # mix, in the 1260 and the console, which is where it happened on the
      # hardware too. The ghost is the same recording as the snare played quiet
      # and short, because that is what a ghost note is.
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
end
