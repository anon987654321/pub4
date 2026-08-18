# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"
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

  # The range must span a FULL OCTAVE, and this one did not.
  #
  # A tempo can always be halved or doubled, so folding an arbitrary reading into
  # a named range only works if the range covers a 2x span. 70 to 110 covers
  # 1.57x, which leaves a hole: anything landing between 111 and 139 folds to
  # neither -- halve it and it falls under 70, double it and it passes 110 -- so
  # the method returned nil however good the reading was.
  #
  # That is not a threshold being strict. It is arithmetic throwing away
  # evidence. One track measured a confidence of 0.499, comfortably above the
  # 0.45 bar and better than takes that were accepted, and was reported as having
  # no readable tempo because its pulse happened to sit at 120.
  #
  # 70 to 140 is exactly one octave and has no hole in it.
  BPM_RANGE = (70.0..140.0)

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
    near_peak = scored.select { |score, _| score >= margin }
    in_range = near_peak.select { |_, tempo| BPM_RANGE.cover?(tempo) }
    return in_range.min_by(&:last).last unless in_range.empty?

    # Nothing scored well inside the range, so fold the winner into it.
    #
    # This is the necessary consequence of the asymmetry noted above, and
    # leaving it out cost three usable tracks. A drum stem locked at 0.722 --
    # a strong, unambiguous reading -- at 159.6 bpm. Half of that is 79.8, which
    # is plainly the tempo a person would name, but the statistic CANNOT confirm
    # it: folding to half doubles the period, which splits one cluster into two
    # opposite ones and scores near nothing. Requiring in-range confirmation
    # therefore rejects every track whose pulse is detected at double time.
    #
    # The confidence check belongs on the peak, which is where the evidence is.
    # Once the pulse is established, halving it is arithmetic, not measurement.
    folded = near_peak.max_by(&:first).last
    folded /= 2.0 while folded > BPM_RANGE.max
    folded *= 2.0 while folded < BPM_RANGE.min
    BPM_RANGE.cover?(folded) ? folded.round(2) : nil
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

    # target_bars was declared and never read, which mattered because the whole
    # point of fitting is to drop the result onto a beat of a known length.
    # take/ratio is only approximately a whole number of bars at to_bpm --
    # atempo rounds, the source bars are measured rather than exact -- so a
    # sixteen-bar take arrives a few tens of milliseconds long or short and the
    # last word either overruns the beat or leaves a hole. Trimming and padding
    # to the exact figure costs nothing and makes the output droppable.
    exact = target_bars ? (60.0 / to_bpm.to_f * 4 * target_bars).round(3) : nil
    tail = exact ? ",atrim=0:#{exact},apad=whole_dur=#{exact}" : ""

    ok = RadioChop.run!("ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                        "-ss", start_sec.round(3).to_s, "-t", take.round(3).to_s, "-i", vocal_path,
                        "-af", "#{atempo_chain(ratio)},#{vocal_tone}#{tail}",
                        "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest,
                        label: "acapella fit")
    return nil unless ok != false && File.file?(dest)

    { path: dest, ratio: ratio.round(4), from_bpm:, to_bpm:,
      seconds: (exact || (take / ratio)).round(2) }
  end

  # A rap vocal wants to sit forward without getting shrill. High-passed to lose
  # the room the separator could not remove, a dip where a beat's own midrange
  # sits so the two do not fight, and levelled so a verse does not shout at a
  # chorus.
  # Sharp, meaning legible -- consonants, not level.
  #
  # What makes a rap vocal cut is the top half of speech: the 3 to 5 kHz band
  # where consonants live, and the air above 8 where breath and sibilance sit.
  # The old chain lifted 2.6 kHz, which is vowel territory -- it made the voice
  # louder and no clearer. These lift the parts that carry the words.
  #
  # A fast compressor after them, not before: the point is to catch consonant
  # peaks once they have been raised, so the quiet ones come up to meet the loud
  # ones. A 2 ms attack is fast enough to see a 't'.
  #
  # The de-esser is what lets the rest of it be this bright. Lifting 8 kHz on a
  # separated stem raises sibilance more than anything else, and a stem carries
  # separation artefacts up there too. adynamicequalizer pulls 6.5 kHz down only
  # while 6.5 kHz is loud, so the brightness stays and the spit does not.
  #
  # No loudnorm. Single-pass loudnorm is DYNAMIC -- it rides the gain through the
  # take, which on a rap vocal flattens the delivery, the loud line and the
  # muttered one arriving at the same level. That is the same fault that was
  # making the master wander, left in the vocal chain when the master was fixed.
  # The darker reading of the same voice.
  #
  # Not simply the bright chain with the treble turned down -- that gives a dull
  # vocal, which is a different thing from a dark one. Dark means the weight
  # moves DOWN rather than the top going away: chest lifted around 220 Hz, the
  # consonant band kept but narrowed and placed lower at 2.8 kHz so the words
  # still arrive, and the air above 7 kHz rolled off rather than boosted.
  #
  # Then tape. An atan waveshaper at low drive adds the odd harmonics that make
  # a voice sound recorded rather than captured, and it is the saturation that
  # stops the result being merely quiet at the top -- there is still something
  # happening up there, it is just harmonic rather than original.
  VOCAL_TONE_DARK = "highpass=f=90," \
                    "equalizer=f=220:t=q:w=1.0:g=2.5," \
                    "equalizer=f=450:t=q:w=1.4:g=-1.5," \
                    "equalizer=f=2800:t=q:w=1.6:g=2.0," \
                    "lowpass=f=7200," \
                    "volume=8dB,asoftclip=type=atan:param=1.8:oversample=4,volume=-8dB," \
                    "acompressor=threshold=-20dB:ratio=3.5:attack=4:release=130:knee=6:makeup=1.7," \
                    "alimiter=limit=0.92:level_out=0.94"

  VOCAL_TONE = "highpass=f=110," \
               "equalizer=f=380:t=q:w=1.2:g=-2.5," \
               "equalizer=f=3800:t=q:w=1.1:g=3.5," \
               "equalizer=f=8500:t=h:w=0.7:g=2.5," \
               "adynamicequalizer=dfrequency=6500:tfrequency=6500:threshold=0.30:" \
               "ratio=3:attack=2:release=60:mode=cutabove," \
               "acompressor=threshold=-20dB:ratio=4:attack=2:release=110:knee=4:makeup=1.9," \
               "alimiter=limit=0.92:level_out=0.94"

  # Which tone a render uses. VOCAL_TONE=dark selects the darker chain.
  def vocal_tone
    ENV["VOCAL_TONE"].to_s.downcase == "dark" ? VOCAL_TONE_DARK : VOCAL_TONE
  end

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

  # Where separated vocals turn up, and the mix each belongs to.
  #
  # Two places, because two different jobs left stems behind. The downloaded
  # acapellas live under scratch/acapella with their source in samples/acapella.
  # But `kit` ran demucs over samples/own -- the operator's own recordings with
  # named collaborators on them -- to dig a drum kit out, and it wrote every
  # stem including the vocals. Those have been sitting there separated and
  # unused, and they are better material than anything downloaded: they are the
  # people who actually made these records.
  # The own-recordings source is OFF by default. Those stems are the operator's
  # collaborators on the operator's own records, and putting them over unrelated
  # beats is a different decision from using a downloaded acapella -- it is their
  # work being repurposed rather than a sample being flipped. OWN_VOCALS=1 opts
  # in deliberately.
  DOWNLOADED_STEMS = { stems: File.join(WORK, "*", "*", "vocals.wav"),
                       mixes: File.join(DEST, "*") }.freeze
  OWN_STEMS = { stems: File.join(ROOT, "scratch", "kit_dig", "*", "*", "vocals.wav"),
                mixes: File.join(ROOT, "samples", "own") }.freeze

  def stem_sources
    ENV["OWN_VOCALS"] == "1" ? [DOWNLOADED_STEMS, OWN_STEMS] : [DOWNLOADED_STEMS]
  end

  def separated
    stem_sources.flat_map do |source|
      Dir[source[:stems]].sort.filter_map do |stem|
        slug = File.basename(File.dirname(stem))
        mix = Dir[File.join(source[:mixes], "#{slug}.*")].first ||
              Dir[File.join(source[:mixes], "*", "#{slug}.*")].first
        next unless mix && File.file?(mix)

        { slug:, stem:, mix: }
      end
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

  # Voices to leave out, and voices to reach for first.
  #
  # Both are operator judgements about performances rather than anything
  # measurable, which is why they are lists of names and not a scoring function.
  # A take can be perfectly separated, perfectly in tempo, and still the wrong
  # one for these beats.
  EXCLUDE = (ENV["VOCAL_EXCLUDE"] || "festival girson,dypt").downcase.split(",").map(&:strip).freeze

  # An allow-list, not a preference. VOCAL_ONLY= names who may appear at all,
  # and nothing outside it is used even if that leaves the pool empty and the
  # track instrumental -- which is the correct outcome, because an instrumental
  # is a track and the wrong rapper is a mistake.
  ONLY = (ENV["VOCAL_ONLY"] || "store p").downcase.split(",").map(&:strip).freeze

  # "prod. Store P" is a production credit, not a performance.
  #
  # Three titles here name Store P and only two of them are him rapping. On
  # "Jaja (prod. Store P)" he made the beat and A-laget are on the microphone,
  # so a plain substring match on his name puts somebody else's voice on the
  # track. The distinction is in the word before the name.
  PRODUCER_CREDIT = /\bprod\.?\s*(by\s*)?/i

  # A feature credit is not a lead vocal either.
  #
  # "Sonar Ut Gmix (feat. John Olav Nilsen, Vågard, Store P, Girson, Lars
  # Vaular, Mats Dawg, Mike T…)" names him eighth on a posse cut, so a verse
  # lifted from the middle of it is far likelier to be one of the other seven.
  # The producer guard already refused "Jaja (prod. Store P)" for the same
  # reason -- his name on the record is not his voice on the microphone -- and a
  # guest spot is the same mistake wearing a different word.
  #
  # "Store P m⧸ Lars Vaular" is deliberately still allowed: there he is the
  # billed artist and Vaular is the guest, which is a record of his with a
  # feature on it rather than someone else's record he appears on.
  FEATURE_CREDIT = /\b(?:feat|ft|featuring)\b\.?/i
  CREDIT = Regexp.union(PRODUCER_CREDIT, FEATURE_CREDIT)

  def performer?(slug, name)
    text = slug.to_s.downcase
    return false unless text.include?(name)

    # Reject when every mention of the name sits behind a credit rather than in
    # the artist position.
    text.split(/[(\[]/).any? do |part|
      part.include?(name) && !part.match?(CREDIT)
    end
  end

  def usable
    index.reject { |v| EXCLUDE.any? { |bad| v["slug"].to_s.downcase.include?(bad) } }
  end

  def ranked
    ok = usable
    return ok if ONLY.empty?

    ok.select { |v| ONLY.any? { |name| performer?(v["slug"], name) } }
  end

  # ------------------------------------------------------------------ laying

  # How far into the original the verse is taken from.
  #
  # Never the opening: a track begins with an intro, a hook, or silence, and
  # what is wanted is the rapper mid-flow. Sixteen bars in, moved on by the
  # track's own name so two beats do not get the same verse.
  # Take the verse from the MIDDLE of the record, as a fraction of its length.
  #
  # A fixed sixteen bars in is a guess that happens to be wrong for most tracks.
  # At around a hundred beats a minute it lands about forty seconds in, which on
  # a four-minute record is still the first hook -- so every beat got the same
  # opening material and none of them got a verse.
  #
  # Measuring from the whole duration instead puts the cut where the rapping
  # actually is. The middle half of a track is verse: the intro and first hook
  # are behind it, the outro and repeat-to-fade ahead of it. Different beats take
  # different points inside that window so they do not all say the same thing.
  VERSE_WINDOW = (0.32..0.68)
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

  # The voice sits IN the track, not on top of it.
  #
  # It was mixed at 1.15 against the beat's 1.0 and ducked the beat by a third,
  # which together put the rapper well out in front -- a vocal-led record, where
  # what is wanted is a beat with someone on it. Now the voice comes in slightly
  # under the beat and the duck is halved, so the words stay legible without the
  # instrumental stepping aside for them.
  #
  # Legibility is not loudness. A gentle duck at the right moment does more for
  # intelligibility than three decibels of level, and costs the track nothing.
  VOCAL_WEIGHT = ENV.fetch("VOCAL_WEIGHT", "0.66")
  VOCAL_DUCK_DB = ENV.fetch("VOCAL_DUCK_DB", "-18")

  MIX_GRAPH = <<~GRAPH.gsub("\n", "")
    [1:a]aformat=channel_layouts=stereo,asplit=2[vox][key];
    [0:a]aformat=channel_layouts=stereo[bt];
    [bt][key]sidechaincompress=threshold=#{VOCAL_DUCK_DB}dB:ratio=2:attack=12:release=260:level_sc=1.0[ducked];
    [ducked][vox]amix=inputs=2:weights=1.0 #{VOCAL_WEIGHT}:duration=first:normalize=0,
    alimiter=limit=0.95:level_out=0.96[out]
  GRAPH

  # Everything above this line was the section: four constants describing where
  # to cut, when to halve, and how to mix -- and no code that read any of them.
  # index! measured every separated vocal and wrote samples/acapella/index.json,
  # and nothing has ever opened that file. The library stopped at the point
  # where it would have been used.
  #
  # (dilla.rb has its own rap-vocal path, rap_vocal_fit! and its thirty
  # neighbours, which places a vocal DURING a render. This is the other job:
  # putting an indexed acapella over a beat that already exists as a file.)

  # Seconds of audio in a file.
  #
  # ffprobe rather than a decode, because the verse offset is a fraction of the
  # WHOLE record and reading its length is cheaper than measuring it.
  def duration(path)
    RadioChop.capture("ffprobe", "-v", "error", "-show_entries", "format=duration",
                      "-of", "default=nokey=1:noprint_wrappers=1", path).to_f
  end

  # One of VERSE_POSITIONS points inside VERSE_WINDOW, chosen by name.
  #
  # MD5 of the name rather than String#hash: Ruby seeds string hashing per
  # process, so the same beat would take a different verse on every run and the
  # "so two beats do not get the same verse" property would be noise instead of
  # a rule. A digest is stable across processes and machines.
  def verse_start(total_sec, seed)
    return 0.0 unless total_sec.to_f.positive?

    slot = Digest::MD5.hexdigest(seed.to_s)[0, 8].to_i(16) % VERSE_POSITIONS
    span = VERSE_WINDOW.max - VERSE_WINDOW.min
    fraction = VERSE_WINDOW.min + (span * slot / (VERSE_POSITIONS - 1).to_f)
    (total_sec.to_f * fraction).round(3)
  end

  # What tempo to actually stretch to, given HALF_TIME_ABOVE.
  #
  # Returns the tempo the vocal is fitted to, which is not always the beat's:
  # over a fast beat the rapper works at half the beat's tempo, one syllable
  # per two beats. The ratio is reported alongside so a caller can say which
  # happened.
  def stretch_plan(from_bpm:, to_bpm:)
    from = from_bpm.to_f
    to = to_bpm.to_f
    return nil unless from.positive? && to.positive?

    half = (to / from) > HALF_TIME_ABOVE
    target = half ? to / 2.0 : to
    { to_bpm: target.round(2), ratio: (target / from).round(4), half_time: half }
  end

  # Beat in, voice on top, one file out. MIX_GRAPH's [0:a] is the beat and
  # [1:a] is the vocal; duration=first means the beat decides the length.
  def lay!(beat:, vocal:, dest:)
    FileUtils.mkdir_p(File.dirname(dest))
    RadioChop.run!("ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                   "-i", beat, "-i", vocal,
                   "-filter_complex", MIX_GRAPH, "-map", "[out]",
                   "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest,
                   label: "acapella lay")
    File.file?(dest) ? dest : nil
  end

  # Which indexed vocal to use. A named slug wins; otherwise the ranked pool,
  # picked by the beat's own name so the same beat always gets the same rapper.
  def choose(slug: nil, seed: nil)
    pool = ranked
    return nil if pool.empty?
    return pool.find { |v| v["slug"].to_s.downcase.include?(slug.to_s.downcase) } if slug

    pool[Digest::MD5.hexdigest(seed.to_s)[8, 8].to_i(16) % pool.length]
  end

  # The whole thing: pick a vocal, cut a verse from a bar line of the original,
  # stretch it to the beat's tempo (or half of it), and mix.
  #
  # bars is how many bars of the BEAT the vocal has to fill, which is why it is
  # passed to fit! as target_bars as well: the take comes from the original's
  # bar grid, the result has to land on ours.
  def over!(beat:, dest:, bpm:, bars: 16, slug: nil, seed: nil)
    entry = choose(slug:, seed: seed || File.basename(beat, ".*"))
    unless entry
      warn "acapella: nothing usable in the index — run `dilla acapella` first" \
           "#{ONLY.empty? ? '' : " (VOCAL_ONLY=#{ONLY.join(',')})"}"
      return nil
    end

    # Every one of these branches used to be a bare `return nil`, which is the
    # failure this library exists to stop being: index.json is written once and
    # scratch/ is cleaned often, so the ordinary case is a row pointing at a
    # stem that is no longer on disk. Saying which one, and what to run, is the
    # difference between a missing file and "nothing laid".
    stem = File.expand_path(entry["stem"], ROOT)
    unless File.file?(stem)
      warn "acapella: #{entry['slug']} is indexed but its stem is gone (#{entry['stem']}) — re-run demucs"
      return nil
    end

    from_bpm = entry["bpm"].to_f
    plan = stretch_plan(from_bpm:, to_bpm: bpm)
    unless plan
      warn "acapella: #{entry['slug']} has no usable tempo (#{entry['bpm'].inspect})"
      return nil
    end

    # Snap the verse offset back to the original's own bar grid, anchored on the
    # downbeat index! measured. Cutting on a bar line is what preserves how the
    # rapper sits against it; cutting on the raw fraction would land mid-bar and
    # the offset that IS the performance would be lost.
    bar = 60.0 / from_bpm * 4
    anchor = entry["start_sec"].to_f
    raw = verse_start(duration(stem), seed || File.basename(beat, ".*"))
    start = anchor + ([((raw - anchor) / bar).floor, 0].max * bar)

    fitted = fit!(vocal_path: stem, dest: File.join(WORK, "fit", "#{entry['slug']}_#{bpm.round}_#{bars}bars.wav"),
                  from_bpm:, to_bpm: plan[:to_bpm], start_sec: start, bars:, target_bars: bars)
    unless fitted
      warn "acapella: #{entry['slug']} will not stretch #{from_bpm} -> #{plan[:to_bpm]} bpm"
      return nil
    end

    laid = lay!(beat:, vocal: fitted[:path], dest:)
    return nil unless laid

    { out: laid, slug: entry["slug"], from_bpm:, to_bpm: plan[:to_bpm],
      half_time: plan[:half_time], start_sec: start.round(3), bars:, fit: fitted[:path] }
  end
end
