# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "radio_chop"

# Putting somebody's vocal on our beat, in time.
#
# The problem is not separation -- demucs does that. The problem is that a rap
# vocal recorded at 94 beats per minute laid over a beat running at 83 drifts
# steadily out of time, and by the end of a verse the rapper is a beat and a
# half early. Syncing it means three things, in this order:
#
#   1. What tempo was the original?
#   2. Where is its first downbeat?
#   3. Stretch it to our tempo without moving its pitch, and start it on our
#      first downbeat.
#
# The first question is the one that decides everything, and it must be asked of
# the FULL TRACK, not the vocal. An isolated vocal has no reliable pulse -- rap
# phrasing sits deliberately across the beat and a rapper may hold a syllable
# through a whole bar. The drums in the original are what state the tempo, and
# they are still there in the mix we downloaded even though we throw them away.
# So the tempo is measured on the mix and applied to the stem.
module Acapella
  ROOT = File.expand_path("..", __dir__)
  WORK = File.join(ROOT, "scratch", "acapella")
  DEST = File.join(ROOT, "samples", "acapella")
  SAMPLE_RATE = 44_100

  # Rap sits here. The detector returns a period, and a period can be read as
  # half or double its true value; the range picks the reading a person would.
  BPM_RANGE = (70.0..110.0)

  module_function

  # ------------------------------------------------------------------ tempo

  # The tempo of the original mix, in beats per minute.
  #
  # Measured from the low band, where the kick lives: the envelope of everything
  # below 180 Hz is very nearly a picture of the kick pattern, and its strongest
  # repeating period is the bar or the beat. RadioChop already does this well
  # enough for loop-finding and the same machinery serves here.
  # Candidate tempos, a fifth of a beat apart. Finer than a listener can name and
  # coarse enough to search in a second.
  SEARCH_RANGE = (60.0..180.0)
  SEARCH_STEP = 0.2

  # A reading is only worth using if the beats genuinely cluster. Below this the
  # track has no steady pulse the method can find, and saying so is better than
  # returning the least-bad number.
  MIN_CONFIDENCE = 0.45

  def tempo(mix_path)
    # Scored by how well the beats land on a grid, not by autocorrelation.
    #
    # The first version borrowed RadioChop.best_period, which finds the strongest
    # repeating period in an envelope. That is the right tool for finding a
    # loopable span and the wrong one for finding a tempo: it returned 98.36 for
    # a track, which is a perfectly plausible rap tempo, and stretching a vocal
    # by it put the syllables 39 ms from the sixteenth-note grid where random
    # placement would give 45. It was not detecting the tempo. It was returning
    # a number.
    #
    # This measures the thing that matters instead. For each candidate tempo,
    # take every onset, and ask where it falls WITHIN one beat -- as an angle
    # round a circle, so a beat's start and end are the same place. If the
    # candidate is right, every onset lands near the same angle and the angles
    # cluster tightly. If it is wrong, they scatter evenly. The length of the
    # average of those angles as unit vectors is exactly that: near 1 for
    # clustered, near 0 for scattered.
    #
    # Handling phase falls out for free, which is why it is done this way: it
    # never has to know WHERE the first beat is to judge whether the spacing is
    # right.
    beats = onset_times(mix_path)
    return nil if beats.length < 24

    scored = []
    bpm = SEARCH_RANGE.min
    while bpm <= SEARCH_RANGE.max
      scored << [clustering(beats, 60.0 / bpm), bpm.round(2)]
      bpm += SEARCH_STEP
    end
    peak = scored.map(&:first).max
    return nil if peak < MIN_CONFIDENCE

    # Take the SLOWEST tempo that still scores near the best, not the best.
    #
    # This statistic is not symmetric between half and double, and assuming it
    # was is what produced a reading of 79.6 at a confidence of 0.029 -- a number
    # the threshold should have rejected and did not, because the check ran
    # before the folding rather than after.
    #
    # Onsets a beat apart also fall on every half-beat and every quarter-beat, so
    # a grid twice as fine fits them just as tightly; a grid twice as COARSE
    # splits them into two opposite clusters and scores nothing. The statistic
    # therefore always prefers faster, and left alone it runs to the top of the
    # search range.
    #
    # The slowest reading consistent with the evidence is the musical one, which
    # is the same rule RadioChop uses when it prefers a longer multiple.
    margin = peak * 0.88
    in_range = scored.select { |score, tempo| score >= margin && BPM_RANGE.cover?(tempo) }
    return nil if in_range.empty?

    in_range.min_by(&:last).last
  end

  # How tightly a set of times clusters when folded into one period.
  #
  # The resultant length of the onsets as angles: 1.0 means every onset falls at
  # the same point in the beat, 0.0 means they are spread evenly and the period
  # means nothing.
  def clustering(times, period)
    return 0.0 unless period.positive?

    sin_sum = 0.0
    cos_sum = 0.0
    times.each do |t|
      angle = 2.0 * Math::PI * ((t % period) / period)
      sin_sum += Math.sin(angle)
      cos_sum += Math.cos(angle)
    end
    Math.sqrt((sin_sum * sin_sum) + (cos_sum * cos_sum)) / times.length
  end

  # Only the strongest few rises count as beats.
  #
  # The first version took every rising edge above a floor 14 dB down from the
  # peak. In a modern rap mix almost everything is within 14 dB of peak, so it
  # returned 1536 onsets across a four-minute track -- seven a second, which is
  # not a kick drum, it is the envelope wobbling. Clustered against every
  # candidate tempo they scored 0.025, indistinguishable from noise, and the
  # detector reported no reading at all.
  #
  # Keeping only the top few percent of RISES fixes it. A kick is a large jump
  # in the low band, and largeness is the whole signal. At the 97th percentile
  # this track yields 144 onsets, 0.6 a second, and they cluster at 0.70 -- a
  # real lock, and stable across neighbouring thresholds, which is the sign that
  # it is finding the music rather than fitting the threshold.
  ONSET_PERCENTILE = 0.96
  ONSET_MIN_GAP_WINDOWS = 10   # 200 ms; kicks are rarely faster

  def onset_times(path)
    env = RadioChop.rms_series(path, filter: RadioChop::BANDS[:kick],
                               window: RadioChop::ENV_WINDOW)
    return [] if env.length < 200

    rises = (1...env.length).filter_map { |i| (d = env[i] - env[i - 1]).positive? ? [d, i] : nil }
    return [] if rises.length < 50

    threshold = rises.map(&:first).sort[(rises.length * ONSET_PERCENTILE).to_i]
    picked = []
    rises.each do |delta, i|
      next if delta < threshold
      next if picked.any? && (i - picked.last) < ONSET_MIN_GAP_WINDOWS

      picked << i
    end
    picked.map { |i| i * RadioChop::ENV_WINDOW }
  end

  # How confident the reading is, for reporting.
  def tempo_confidence(mix_path, bpm)
    clustering(onset_times(mix_path), 60.0 / bpm).round(3)
  end

  # Where the first beat lands.
  #
  # The first moment the low band rises decisively above its own floor. Tracks
  # start with silence, an intro, a spoken word; what we want is the first kick,
  # because everything after it is on the grid.
  def first_downbeat(mix_path)
    env = RadioChop.rms_series(mix_path, filter: RadioChop::BANDS[:kick],
                               window: RadioChop::ENV_WINDOW)
    return 0.0 if env.length < 100

    peak = env.max
    floor = peak - 12.0
    idx = env.index { |v| v > floor }
    idx ? (idx * RadioChop::ENV_WINDOW).round(3) : 0.0
  end

  # ------------------------------------------------------------------ fitting

  # Stretches a vocal to our tempo and starts it on our downbeat.
  #
  # atempo changes duration WITHOUT changing pitch, which is the whole reason it
  # is used here rather than a varispeed: a rapper resampled from 94 to 83 bpm
  # would come out a whole tone lower and sound like a different person. atempo
  # is limited to a factor of two per instance, so large moves are split across
  # several -- which is also gentler, since each pass has less to do.
  #
  # The vocal is cut from a bar boundary of the ORIGINAL, not from the first
  # word. Rap does not begin on the one; it begins wherever the rapper felt like
  # coming in, and that relationship to the bar is the performance. Preserve the
  # offset and it lands the same way over our beat.
  def fit!(vocal_path:, dest:, from_bpm:, to_bpm:, start_sec:, bars:, target_bars: nil)
    ratio = to_bpm.to_f / from_bpm.to_f
    return nil unless ratio.positive? && ratio.between?(0.25, 4.0)

    beat = 60.0 / from_bpm.to_f
    # Take whole bars of the original so the phrasing arrives intact.
    take = beat * 4 * bars
    FileUtils.mkdir_p(File.dirname(dest))

    ok = RadioChop.run!("ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                        "-ss", start_sec.round(3).to_s, "-t", take.round(3).to_s, "-i", vocal_path,
                        "-af", "#{atempo_chain(ratio)},#{VOCAL_TONE}",
                        "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest,
                        label: "acapella fit")
    return nil unless ok != false && File.file?(dest)

    { path: dest, ratio: ratio.round(4), from_bpm:, to_bpm:,
      seconds: (take / ratio).round(2) }
  end

  # A rap vocal wants to sit forward without getting shrill. High-passed to lose
  # the room the separator could not remove, a dip where a beat's own midrange
  # sits so the two do not fight, and levelled so a verse does not shout at a
  # chorus.
  VOCAL_TONE = "highpass=f=110," \
               "equalizer=f=380:t=q:w=1.2:g=-2.0," \
               "equalizer=f=2600:t=q:w=1.0:g=2.0," \
               "acompressor=threshold=-18dB:ratio=3:attack=6:release=140:makeup=1.2," \
               "loudnorm=I=-17:TP=-2:LRA=7"

  # atempo handles 0.5x to 2x per instance. Anything beyond gets chained.
  def atempo_chain(ratio)
    parts = []
    remaining = ratio
    while remaining > 2.0
      parts << "atempo=2.0"
      remaining /= 2.0
    end
    while remaining < 0.5
      parts << "atempo=0.5"
      remaining *= 2.0
    end
    parts << "atempo=#{remaining.round(6)}"
    parts.join(",")
  end

  # ----------------------------------------------------------------- pipeline

  # Every separated vocal we have, paired with the mix it came from.
  def separated
    Dir[File.join(WORK, "*", "*", "vocals.wav")].sort.filter_map do |stem|
      slug = File.basename(File.dirname(stem))
      mix = Dir[File.join(DEST, "*", "#{slug}.*")].first
      next unless mix && File.file?(mix)

      { slug:, stem:, mix: }
    end
  end

  # Measures each separated vocal against its own mix and records what it found.
  # Nothing is fitted here: a vocal is fitted to a particular beat at a
  # particular tempo, and that belongs to the render, not to the library.
  def index!
    found = separated
    if found.empty?
      puts "no separated vocals under #{WORK.sub("#{ROOT}/", '')} — run yt-dlp and demucs first"
      return []
    end

    entries = found.filter_map do |item|
      bpm = tempo(item[:mix])
      unless bpm
        puts format("  %-46s no readable tempo — skipped", item[:slug][0, 44])
        next
      end

      start = first_downbeat(item[:mix])
      puts format("  %-46s %6.2f bpm  first beat %.2fs", item[:slug][0, 44], bpm, start)
      { "slug" => item[:slug], "stem" => item[:stem].sub("#{ROOT}/", ""),
        "mix" => item[:mix].sub("#{ROOT}/", ""), "bpm" => bpm, "start_sec" => start }
    end

    FileUtils.mkdir_p(DEST)
    File.write(File.join(DEST, "index.json"),
               "#{JSON.pretty_generate({ 'version' => 1, 'vocals' => entries })}\n")
    puts "\n#{entries.length} vocal(s) indexed"
    entries
  end

  def index
    path = File.join(DEST, "index.json")
    File.file?(path) ? (JSON.parse(File.read(path))["vocals"] || []) : []
  end

  # Picks one vocal for a track, always the same one for the same track name.
  def for_track(track, seed_hash)
    all = index
    return nil if all.empty?

    all[seed_hash % all.length]
  end

  # ------------------------------------------------------------------ laying

  # How far into the original the verse is taken from.
  #
  # Never the opening: a track begins with an intro, a hook, or silence, and
  # what is wanted is the rapper mid-flow. Sixteen bars in, moved on by the
  # track's own name so two beats do not get the same verse.
  VERSE_ENTRY_BARS = 16
  VERSE_STRIDE_BARS = 6
  VERSE_POSITIONS = 7

  # Beyond this much speeding up, take half the tempo instead.
  #
  # A rapper stretched from 85 to 145 beats per minute is being asked to deliver
  # the same words in six-tenths of the time. atempo keeps the pitch, so it does
  # not chipmunk -- it simply becomes a blur, and nobody raps at 145 anyway. Over
  # fast music a rapper works in HALF TIME: the beat is at 145 and the flow is at
  # 72.5, one syllable per two beats rather than one per beat. That is not a
  # compromise, it is what the form does.
  HALF_TIME_ABOVE = 1.35

  # The tempo the voice should actually be fitted to.
  def flow_tempo(vocal_bpm, beat_bpm)
    target = beat_bpm.to_f
    target /= 2.0 while (target / vocal_bpm.to_f) > HALF_TIME_ABOVE
    target
  end

  # Lays a fitted vocal over a finished beat.
  #
  # The beat ducks under the voice rather than the voice being pushed above the
  # beat. Those sound different: raising the vocal makes it loud, while lowering
  # everything else around it makes it CLEAR, and clarity is what carries words.
  # The key is the vocal itself, so the beat only steps back while someone is
  # actually speaking and comes straight back up in the gaps.
  def lay_on!(beat_path:, dest:, seed: 0, vocal: nil, beat_bpm: nil)
    entry = vocal || index[seed % [index.length, 1].max]
    return nil unless entry && File.file?(File.expand_path(entry["stem"], ROOT))

    beat_tempo = beat_bpm || tempo(beat_path)
    return nil unless beat_tempo

    # Half time over fast music, rather than sprinting the rapper.
    target = flow_tempo(entry["bpm"], beat_tempo)

    beat = 60.0 / entry["bpm"].to_f
    offset_bars = VERSE_ENTRY_BARS + ((seed % VERSE_POSITIONS) * VERSE_STRIDE_BARS)
    start = entry["start_sec"].to_f + (beat * 4 * offset_bars)

    duration = probe_seconds(beat_path)
    return nil unless duration&.positive?

    # Enough bars of the original that, once stretched, it covers the beat.
    bars = ((duration * (entry["bpm"].to_f / target) / (beat * 4)).ceil + 1)
    fitted = File.join(File.dirname(dest), "#{File.basename(dest, '.*')}_vox.wav")
    fit = fit!(vocal_path: File.expand_path(entry["stem"], ROOT), dest: fitted,
               from_bpm: entry["bpm"].to_f, to_bpm: target, start_sec: start, bars:)
    return nil unless fit

    ok = system("ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                "-i", beat_path, "-i", fitted,
                "-filter_complex", MIX_GRAPH, "-map", "[out]",
                "-c:a", "libmp3lame", "-b:a", "192k", dest,
                out: File::NULL, err: File::NULL)
    FileUtils.rm_f(fitted)
    return nil unless ok && File.file?(dest)

    { path: dest, vocal: entry["slug"], from_bpm: entry["bpm"], to_bpm: target,
      ratio: fit[:ratio], verse_bars_in: offset_bars }
  end

  MIX_GRAPH = <<~GRAPH.gsub("\n", "")
    [1:a]aformat=channel_layouts=stereo,asplit=2[vox][key];
    [0:a]aformat=channel_layouts=stereo[bt];
    [bt][key]sidechaincompress=threshold=-22dB:ratio=3:attack=8:release=220:level_sc=1.0[ducked];
    [ducked][vox]amix=inputs=2:weights=1.0 1.15:duration=first:normalize=0,
    alimiter=limit=0.95:level_out=0.96[out]
  GRAPH

  def probe_seconds(path)
    out = IO.popen(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                    "-of", "csv=p=0", path], &:read)
    value = out.to_s.strip.to_f
    value.positive? ? value : nil
  end
end
