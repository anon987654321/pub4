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

  # Every pass is written down before it is heard. The rig was ephemeral once and
  # a swept scratchpad took the takes with it -- the same defect that lost the
  # crate: provenance living somewhere more fragile than what it describes.
  def journal!(row)
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
    ranked = beds.sort_by { |b| -worth.fetch(slug_of.call(b), 0.35).to_f }
    pool = ranked.size >= 8 ? ranked.first((ranked.size * 0.5).ceil) : ranked
    seen = recency
    bed = pool.min_by { |b| [seen.fetch(slug_of.call(b), -1), rand] }
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
  # Appends its own four sources and returns the index of the last one, which is
  # the crackle: the hats and the record noise are the same long pink generator,
  # read twice. That is not a saving, it is the sound -- 0.006 amplitude pink
  # through a 7.2 kHz high-pass is the hat, and the same noise unfiltered is the
  # surface the whole thing sits on, so they share a grain no two generators
  # would. ffmpeg splits the input for the second reader on its own.
  def drunk_kit(n, inputs, graph, beat:, bar:, step:, sxt:, total:)
    inputs << "-f lavfi -t 0.32 -i sine=f=52:d=0.32"
    inputs << "-f lavfi -t 0.24 -i anoisesrc=c=pink:d=0.24"
    inputs << "-f lavfi -t 0.05 -i anoisesrc=c=white:d=0.05"
    inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.006"

    jit = ->(ms) { (rand * ms * 2 - ms).round(1) }
    hits = {
      kick: [0.0, (bar / 2 + step)].map { |t| [(t * 1000).round + jit.call(9), 0].max },
      snare: [beat, beat * 3].map { |t| (t * 1000).round + 22 + jit.call(7) }, # behind the grid
      ghost: [(beat * 2 + sxt), (beat * 3 + sxt * 3)].map { |t| (t * 1000).round + jit.call(14) },
      hat: (0...8).map { |i| (i * step * 1000).round + (i.odd? ? 34 : 0) + jit.call(6) },
    }
    graph.concat place(n, "kk", "volume=1.9,afade=t=out:st=0.015:d=0.24,lowpass=f=180," \
                                "acrusher=bits=12:mode=log:aa=1", hits[:kick])
    graph.concat place(n + 1, "sn", "volume=1.5,afade=t=out:st=0.004:d=0.19," \
                                    "bandpass=f=1900:width_type=h:w=2600,volume=1.4", hits[:snare])
    graph.concat place(n + 2, "gh", "volume=0.24,afade=t=out:st=0.003:d=0.09," \
                                    "bandpass=f=2400:width_type=h:w=1800", hits[:ghost])
    graph.concat place(n + 3, "hh", "volume=0.26,afade=t=out:st=0.002:d=0.048,highpass=f=7200", hits[:hat])
    graph << "[kk][sn][gh][hh]amix=inputs=4:weights=2.8 2.4 1.1 1.0:normalize=0[kit_raw]"
    graph << "[kit_raw]#{sonitex(bits: 11, lo: 42, hi: 12000, drive: 1.18)}," \
             "#{vcs(depth: 0.42, smear: 2.1)}[kit]"
    { hits: hits, crackle_i: n + 3 }
  end

  def play!(inputs, graph, banner)
    warn banner
    cmd = "#{FF} -nostdin -loglevel error #{inputs.join(' ')} " \
          "-filter_complex #{graph.join('; ').shellescape} -map \"[out]\" -f wav -"
    exec("/bin/zsh", "-c",
         "#{cmd} 2>/dev/null | #{FFPLAY} -nodisp -autoexit -loglevel quiet -i - 2>/dev/null")
  end
end
