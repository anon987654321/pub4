# frozen_string_literal: true

require_relative "frozen_state"
require "fileutils"
require "json"
require "open3"
require "time"

# One long radio capture in, a rack of registered sample loops out.
#
# The engine already knows what to do with a sampled bed -- TRACK_SAMPLE_LOOPS
# names four of them and build_sample_loop_filter mixes them alongside drums and
# harmony on their own bus. What it had no way to do was find one. Every entry
# in that table was cut by hand, and the notes above them record how much
# measurement each took: where the passage actually starts, which bar length
# rejoins itself, whether the record's own low end is in the way.
#
# samples/ubrukte_samples.mp3 is 18.5 minutes of continuous Sheger FM off-air.
# There is not one silence longer than 0.6s in it at -38 dB, so it cannot be
# split on gaps -- it has to be split on music. That is what this does, and it
# does it in the order a producer would:
#
#   1. scan    band energy over the whole broadcast, cheap, on the raw mix
#   2. propose windows that are loud, steady, and more musical than spoken
#   3. strip   demucs 6-stem, keeping bass/guitar/piano/other and dropping
#              drums and vocals -- the two things asked for
#   4. cut     bar-aligned to the RAW mix's kick onsets, because the drums are
#              the only reliable clock and we still have them at this point
#   5. measure key, loop rejoin, low-versus-mid, air; write the same hp/sub_db/
#              lp fields the hand-cut entries carry
#   6. register into samples/chopped/loops.json, which TRACK_SAMPLE_LOOPS merges
#
# Order matters at step 3/4. Demucs is run BEFORE the final trim but the trim
# offsets come from onsets detected on the mix WITH its drums: a drumless
# instrumental has no transients to align to, and a loop that starts off the
# beat is unusable no matter how clean the separation was.
#
# Deliberately not the stems path (stems_register / use_stem_harmony). That
# replaces the harmonic bus with the sample. These are beds -- they play under
# the arrangement, which is what the source is good for.
module RadioChop
  ROOT = File.expand_path("..", __dir__)
  DEST = File.join(ROOT, "samples", "chopped")
  REGISTRY = File.join(DEST, "loops.json")
  DEFAULT_SOURCE = File.join(ROOT, "samples", "ubrukte_samples.mp3")

  # What a capture is, recorded because a registry row saying only
  # "ubrukte_samples.mp3" cannot answer where the material came from.
  #
  # And the part worth saying out loud, in the same terms lib/crate_dig.rb uses
  # about the YouTube rips under samples/: an off-air broadcast recording is not
  # licensed material. Chopping it does not clear it, and neither does removing
  # the drums and the vocals. CrateDig exists because that distinction matters
  # and because the public-domain and CC-BY routes are real. Nothing here checks
  # rights or can -- `rights` is carried as "unlicensed" so that a beat built on
  # one of these rows can be identified later rather than discovered at release.
  SOURCE_RIGHTS = "unlicensed — off-air broadcast capture, not cleared for release"
  SOURCE_LABELS = {
    "ubrukte_samples" => "Sheger FM (Addis Ababa) off-air capture",
  }.freeze

  # htdemucs_6s rather than the 4-stem htdemucs_ft used for vocal isolation
  # elsewhere. The 4-stem model folds guitar and piano into `other`, which is
  # survivable, but the 6-stem split lets a candidate be rejected for having
  # nothing but `other` in it -- i.e. for being texture rather than playing.
  MODEL = "htdemucs_6s"
  KEEP_STEMS = %w[bass guitar piano other].freeze
  DROP_STEMS = %w[drums vocals].freeze

  SAMPLE_RATE = 44_100
  # Analysis rate for the in-Ruby passes. 22.05k keeps everything the loop
  # decisions depend on (the top band that matters here dies around 6 kHz) at a
  # quarter of the samples to walk.
  ANALYSIS_RATE = 22_050

  # Named so the reasoning survives the numbers.
  #   low    what a highpass would be taking out
  #   body   the reference band for every relative measurement below
  #   speech intelligibility band -- presenters, not singing
  #   air    where a band-limited off-air source stops having content
  #   kick   the clock, used only on the raw mix
  BANDS = {
    low: "highpass=f=40,lowpass=f=120",
    body: "highpass=f=300,lowpass=f=2000",
    speech: "highpass=f=300,lowpass=f=3400",
    air: "highpass=f=6000",
    kick: "highpass=f=50,lowpass=f=220",
  }.freeze

  module_function

  # --- shell ------------------------------------------------------------------
  #
  # Not sh! from dilla.rb, and the reason is the 120s DILLA_SH_TIMEOUT: a demucs
  # pass over four minutes of candidate audio runs well past it on CPU, so every
  # ingest would be killed partway through separation and report a timeout as if
  # the tool were broken. Long jobs here run uncapped and report their own
  # failure.
  def run!(*argv, label: nil, quiet: true)
    argv = argv.flatten.map(&:to_s)
    ok = if quiet
           system(*argv, out: File::NULL, err: File::NULL)
         else
           # Separation is minutes of work with a progress bar. Swallowing it
           # leaves the caller looking at a stalled terminal with no way to tell
           # a slow model from a hung one.
           system(*argv)
         end
    raise "#{label || File.basename(argv.first)} failed" unless ok

    true
  end

  def capture(*argv)
    out, = Open3.capture2(*argv.flatten.map(&:to_s))
    out
  end

  # --- measurement ------------------------------------------------------------

  # One RMS reading per `window` seconds. No -t cap on purpose: the point of the
  # first pass is the shape of the entire broadcast, and DeepAudio.band_rms
  # stops at 120s of 1111.
  #
  # asetnsamples, NOT astats' own reset/length pair, and this is the difference
  # between a series that means something and one that does not. In
  #
  #   astats=metadata=1:reset=1:length=0.5
  #
  # `length` sets the window for astats' peak/trough RMS readings only, while
  # `reset=1` resets and prints every one AUDIO FRAME -- about 26ms off an mp3
  # decoder, not 0.5s. Measured on the first 60 seconds of the default source
  # that graph emits 2298 readings where 120 were intended, so every index in
  # the series stood for 1/19th of the time the caller thought it did: the scan
  # proposed windows at 5-hour timestamps in an 18-minute file.
  #
  # asetnsamples fixes the frame size before astats sees it, so one frame IS one
  # window and reset=1 means what it reads as. aresample first because the count
  # is in samples and the arithmetic needs a known rate.
  #
  # Worth knowing when reading the rest of the engine: RadioBergenStudy::DeepAudio
  # .band_rms builds the same graph the same wrong way, so its `window:` argument
  # is off by the same factor everywhere it is used. Not corrected from here --
  # the thresholds and min_gap values in the wonky drum learner were tuned
  # against that series and would all shift under it.
  #
  # "-inf" is dropped rather than read: String#to_f turns it into 0.0, which is
  # full scale, so a digital-silence window would score as the loudest thing in
  # the file.
  def rms_series(path, filter: "anull", window: 0.5, from: nil, dur: nil)
    argv = ["ffmpeg", "-hide_banner", "-loglevel", "error"]
    argv += ["-ss", from.round(3).to_s] if from
    argv += ["-t", dur.round(3).to_s] if dur
    argv += ["-i", path, "-af",
             "#{filter},aresample=#{SAMPLE_RATE},asetnsamples=n=#{(SAMPLE_RATE * window).to_i}:p=0," \
             "astats=metadata=1:reset=1," \
             "ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-",
             "-f", "null", "-"]
    capture(*argv).lines.filter_map do |line|
      next unless line.include?("RMS_level=")

      raw = line.split("=").last.strip
      next if raw.include?("inf") || raw.empty?

      value = raw.to_f
      value.finite? ? value : nil
    end
  end

  # Mean of a dB series. Averaging decibels is not averaging power and the two
  # disagree on anything peaky -- but every use below is one band against
  # another over the same window, where the error is common to both and cancels.
  def mean(series) = series.empty? ? nil : series.sum / series.length

  def stddev(series)
    return 0.0 if series.length < 2

    m = mean(series)
    Math.sqrt(series.sum { |v| (v - m)**2 } / (series.length - 1))
  end

  def pcm_mono(path, rate: ANALYSIS_RATE)
    raw, = Open3.capture2("ffmpeg", "-v", "error", "-i", path,
                          "-ac", "1", "-ar", rate.to_s, "-f", "s16le", "-", binmode: true)
    raw.to_s.unpack("s<*").map { |s| s / 32_768.0 }
  end

  def rms(frames)
    return 0.0 if frames.nil? || frames.empty?

    Math.sqrt(frames.sum { |f| f * f } / frames.length)
  end

  def db(value) = value.positive? ? 20.0 * Math.log10(value) : -120.0

  # --- 1/2: scan and propose --------------------------------------------------

  # A window is worth separating if it is loud, level, and carrying more energy
  # outside the speech band than inside it.
  #
  # The musicality term is a proxy and is treated as one: it survives a presenter
  # talking over a bed, which is exactly the case demucs is being asked to fix.
  # It only has to be good enough to stop the expensive pass being spent on
  # four minutes of studio chat. What actually decides a loop is measured after
  # separation, on the instrumental, where the question is answerable.
  def propose(path, want:, span:, window: 0.5)
    full = rms_series(path, window:)
    return [] if full.length < 8

    low = rms_series(path, filter: BANDS[:low], window:)
    speech = rms_series(path, filter: BANDS[:speech], window:)
    air = rms_series(path, filter: BANDS[:air], window:)
    frames = [full, low, speech, air].map(&:length).min

    sorted = full.first(frames).sort
    median = sorted[sorted.length / 2]
    floor = median - 5.0

    per_window = (span / window).ceil
    # Stride of one second. Finer buys nothing -- the trim below re-places the
    # start on a kick onset anyway, so this only has to land in the right
    # passage, not on the right beat.
    stride = (1.0 / window).round

    scored = (0..(frames - per_window)).step(stride).filter_map do |i|
      slice = full[i, per_window]
      next if slice.nil? || slice.length < per_window

      level = mean(slice)
      next if level < floor

      musicality = mean((0...per_window).map { |k| ((low[i + k] + air[i + k]) / 2.0) - speech[i + k] })
      steadiness = stddev(slice)
      {
        start: i * window,
        level: level.round(2),
        musicality: musicality.round(2),
        steadiness: steadiness.round(2),
        # Steadiness is subtracted, not thresholded: a window straddling a
        # segue is not disqualified, it loses to one that does not.
        score: (musicality - steadiness).round(3),
      }
    end

    pick_spread(scored, want:, gap: span * 1.5)
  end

  # Best-first with a minimum separation. Without it the top `want` windows come
  # back as `want` one-second shifts of the same passage, and the rack is one
  # loop reported as eight.
  def pick_spread(scored, want:, gap:)
    chosen = []
    scored.sort_by { |c| -c[:score] }.each do |cand|
      break if chosen.length >= want
      next if chosen.any? { |c| (c[:start] - cand[:start]).abs < gap }

      chosen << cand
    end
    chosen.sort_by { |c| c[:start] }
  end

  # --- 3: separate ------------------------------------------------------------

  # Every cut in one demucs invocation. The model load dominates a short file --
  # separating twelve ten-second cuts one call at a time pays for htdemucs_6s
  # twelve times over.
  #
  # Cuts whose stems are already on disk are skipped, which is the whole point of
  # naming them after their source window. Separation is minutes of the run and
  # nothing about it changes when the scoring does, so re-tuning what gets kept
  # should not cost another pass. CHOP_FRESH=1 clears the lot.
  def stem_dir_for(cut, out_dir) = File.join(out_dir, MODEL, File.basename(cut, ".*"))

  def separated?(dir) = KEEP_STEMS.all? { |s| File.file?(File.join(dir, "#{s}.wav")) }

  def separate!(cuts, demucs:, out_dir:)
    FileUtils.mkdir_p(out_dir)
    todo = cuts.reject { |c| separated?(stem_dir_for(c, out_dir)) }
    if todo.empty?
      puts "chop: stems already separated for all #{cuts.length} cuts — reusing"
    else
      puts "chop: #{cuts.length - todo.length} cached, separating #{todo.length}" if todo.length < cuts.length
      run!(*demucs, "-n", MODEL, "-o", out_dir, *todo, label: "demucs", quiet: false)
    end
    cuts.to_h { |c| [c, stem_dir_for(c, out_dir)] }
  end

  # The sum that IS the deliverable: everything demucs found except drums and
  # vocals.
  #
  # normalize=0 is not optional. amix defaults to dividing by the input count,
  # so the four kept stems would come back 12 dB below the record they were
  # taken from -- and demux_deep_bands!'s `instrumental` sum, which does leave
  # the default in place, is quiet for exactly that reason. Summed at unity
  # these reconstruct the source minus what was removed, at the source's level.
  def instrumental!(stem_dir, dest)
    inputs = KEEP_STEMS.map { |s| File.join(stem_dir, "#{s}.wav") }.select { |p| File.file?(p) }
    return nil if inputs.empty?

    argv = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    inputs.each { |p| argv += ["-i", p] }
    labels = inputs.each_index.map { |i| "[#{i}:a]" }.join
    argv += ["-filter_complex", "#{labels}amix=inputs=#{inputs.length}:duration=longest:normalize=0[out]",
             "-map", "[out]", "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest]
    run!(*argv, label: "instrumental sum")
    dest
  end

  # --- 4: bar-aligned trim ----------------------------------------------------

  # Kick onsets from the RAW cut, before separation. Deliberate: the instrumental
  # has had its transients removed along with the drums, so onset detection on it
  # finds note attacks at best and nothing at worst, and a bed that starts a
  # sixteenth late reads as a mistake however clean it is.
  #
  # deep.detect_onsets is reused because it is pure array arithmetic and correct
  # given a correct series. deep.band_rms is not used to build that series -- see
  # the note on rms_series for why its window argument cannot be believed.
  #
  # deep.estimate_bpm is NOT used, and that is a decision rather than an
  # oversight. It reports the median gap between onsets, which on this material
  # returns the frame quantisation rather than a tempo: the first pass over this
  # broadcast came back with 66.7 BPM for four unrelated passages, 66.7 being
  # exactly 18 frames of 0.05s. Its octave fold cannot correct that either --
  # `raw *= 2 while raw < 70` then `raw /= 2 while raw > 105` sends 66.7 to 133.4
  # and straight back to 66.7, so the function can and does return values below
  # its own floor. Tempo here comes from the loop length instead; see
  # bars_and_bpm.
  ONSET_WINDOW = 0.05

  def kick_series(path) = rms_series(path, filter: BANDS[:kick], window: ONSET_WINDOW)

  def onsets_sec(path, deep:, series: nil)
    series ||= kick_series(path)
    deep.detect_onsets(series, threshold_db: -20.0, min_gap: 4).map { |i| i * ONSET_WINDOW }
  end

  # How well the loop meets itself. The hand-cut entries were settled this way
  # -- "8.421s rejoins itself at -1.1 dB, 8.000s at -8.6 dB" in the note above
  # lo_borges -- so the same measurement decides it here, and the winning value
  # is recorded rather than described.
  #
  # Two terms, because they catch different faults: an edge level mismatch is
  # audible as a pump on every repeat, and a sample-value step is audible as a
  # click even when the levels agree.
  EDGE_SEC = 0.08

  def rejoin(pcm, rate, start_idx, length_idx)
    edge = (rate * EDGE_SEC).to_i
    return nil if length_idx < edge * 2

    head = pcm[start_idx, edge]
    tail = pcm[start_idx + length_idx - edge, edge]
    return nil unless head&.length == edge && tail&.length == edge

    level = (db(rms(tail)) - db(rms(head))).abs
    step = (pcm[start_idx + length_idx - 1].to_f - pcm[start_idx].to_f).abs
    { level_db: level.round(2), step: step.round(4), cost: (level + (step * 20.0)).round(3) }
  end

  def pearson(a, b)
    ma = a.sum / a.length
    mb = b.sum / b.length
    num = (0...a.length).sum { |i| (a[i] - ma) * (b[i] - mb) }
    den = Math.sqrt((0...a.length).sum { |i| (a[i] - ma)**2 } * (0...b.length).sum { |i| (b[i] - mb)**2 })
    den.positive? ? num / den : 0.0
  end

  # What length does this passage repeat at?
  #
  # Asked directly, of the energy envelope, by correlating each candidate length
  # against the material immediately following it. The first version of this
  # module went the other way -- detect a tempo, multiply up to a bar count,
  # take that as the length -- and it does not work on this source: tempo
  # detection needs onsets, and semua_untuk_mu's note already records the case
  # where there are none ("a sustained melodic passage rather than a rhythmic
  # loop... bar arithmetic against a known-good boundary is the only honest way
  # to get a tempo here").
  #
  # Turned around, the same fact is a route rather than an obstacle. Find the
  # length; the tempo follows from it. Checked against the four hand-cut loops
  # by looping each one three times and asking this function for its length:
  #
  #   kembara_rindu  10.43s   found 10.44 (x2)   semua_untuk_mu 10.00s  found 10.00
  #   rauingar        5.22s   found  5.22        lo_borges       8.42s  found  8.42
  #
  # The x2 on kembara_rindu is the reason for the multiple check below. Raw, it
  # returns 5.22 at r=0.971 -- a real answer to a narrower question, since that
  # loop's 4 bars contain a 2-bar figure played twice. lo_borges's note names the
  # trap exactly: "self-similarity finds the shortest thing that repeats, which
  # is not necessarily the musical unit". So a multiple is preferred whenever it
  # still holds up, and the margin is what "still holds up" means.
  ENV_WINDOW = 0.02
  MULTIPLE_MARGIN = 0.06

  def envelope(path) = rms_series(path, window: ENV_WINDOW)

  def correlation_at(env, frames)
    a = env[0, frames]
    b = env[frames, frames]
    return nil unless a&.length == frames && b&.length == frames

    pearson(a, b)
  end

  def best_period(env, lo:, hi:)
    candidates = ((lo / ENV_WINDOW).round..(hi / ENV_WINDOW).round).filter_map do |n|
      c = correlation_at(env, n)
      c ? [c, n] : nil
    end
    return nil if candidates.empty?

    best_c, best_n = candidates.max_by(&:first)
    4.downto(2) do |k|
      c = correlation_at(env, best_n * k)
      # The margin IS the check. An AstFixer autofix pass deleted it in
      # e7e48eed1, which left the trailing backslash behind: `return {...} \`
      # continued onto the loop's own `end`, which parses, so the file stayed
      # Syntax OK and the commit reported "all parse; both engines boot".
      #
      # What it did was return on the FIRST iteration unconditionally. Every
      # loop this function measured came back as best_n * 4 with multiple: 4 --
      # four times too long whenever the 4x window fit, and a NoMethodError on
      # nil.round when it did not. The four hand-cut verifications in the
      # comment above (kembara_rindu 10.44, semua_untuk_mu 10.00, rauingar 5.22,
      # lo_borges 8.42) had all been true and none of them were any more.
      return { seconds: (best_n * k * ENV_WINDOW).round(3), correlation: c.round(3), multiple: k } \
        if c && c >= best_c - MULTIPLE_MARGIN
    end
    { seconds: (best_n * ENV_WINDOW).round(3), correlation: best_c.round(3), multiple: 1 }
  end

  # Tempo from length, which is the direction that works here.
  #
  #   bpm = 240 * bars / seconds
  #
  # Reading the four hand-cut lengths back through it returns each entry's
  # declared BPM exactly: 10.43s over 4 bars is 92, 10.00s over 4 is 96, 5.22s
  # over 2 is 92, 8.42s over 4 is 114. Those four numbers were arrived at
  # independently -- lo_borges's 114 over 120 took a rejoin measurement to
  # settle -- so agreeing with all of them is a real check and not a tautology.
  #
  # The order of BAR_CHOICES does not decide anything, and it is worth saying why
  # rather than leaving it looking like a preference. Over a 70-140 BPM range the
  # lengths each bar count can explain are 1.71-3.43s for 1 bar, 3.43-6.86 for 2,
  # 6.86-13.71 for 4 and 13.71-27.43 for 8 -- because the range is exactly one
  # octave wide, they tile it without overlapping. Any length admits exactly one
  # answer, so first-match is the only match.
  #
  # When nothing matches, bpm is 0, which build_sample_loop_filter already treats
  # as "play at native speed" (`ratio = loop_bpm.positive? ? ... : 1.0`). A wrong
  # tempo is worse than no tempo: it does not fail, it varispeeds the bed to a
  # rate nothing else in the mix is at.
  BPM_RANGE = (70.0..140.0)
  BAR_CHOICES = [8, 4, 2, 1].freeze

  def bars_and_bpm(seconds)
    BAR_CHOICES.each do |bars|
      bpm = 240.0 * bars / seconds
      return [bars, bpm.round(1)] if BPM_RANGE.cover?(bpm)
    end
    [nil, 0.0]
  end

  # Length says what to take, the rejoin says where to start taking it. Starts
  # are the raw mix's own kick onsets rather than a grid: the aim is to begin on
  # a beat that exists rather than on one arithmetic says should.
  def best_trim(pcm, env, rate:, onsets:, cut_sec:, min_sec: 2.0, max_sec: 14.0)
    period = best_period(env, lo: min_sec, hi: [max_sec, (cut_sec / 2.0) - ENV_WINDOW].min)
    return nil unless period

    length_sec = period[:seconds]
    length_idx = (length_sec * rate).to_i
    starts = [0.0] + onsets.select { |t| t + length_sec <= cut_sec }
    best = starts.filter_map { |t| rejoin(pcm, rate, (t * rate).to_i, length_idx)&.merge(start: t.round(3)) }
                 .min_by { |r| r[:cost] }
    return nil unless best

    bars, bpm = bars_and_bpm(length_sec)
    best.merge(length: length_sec, bars:, bpm:,
               self_similarity: period[:correlation], period_multiple: period[:multiple])
  end

  # --- 5: the fields a registered loop has to carry ---------------------------

  # hp / sub_db / lp are the three per-loop corrections build_sample_loop_filter
  # reads. The first attempt here derived all three from the loop's own spectrum,
  # calibrated against the four hand-cut entries. Measured against those four, it
  # does not work, and it is worth writing down why rather than shipping a
  # derivation that fails its own calibration.
  #
  # Low-versus-mid, this module's bands (40-120 Hz against 300-2000 Hz):
  #
  #   kembara_rindu  -4.46   hand hp 90 / sub -7
  #   lo_borges      -5.86   hand hp 60 / sub -3
  #   rauingar       +1.88   hand hp 60 / sub -3
  #   semua_untuk_mu +0.46   hand hp 45 / sub  0
  #
  # kembara_rindu and lo_borges land near the untreated -4.9 and -6.6 those notes
  # quote, so the instrument is not broken -- but semua_untuk_mu reads +0.46 here
  # against the -10.3 in its note, and +0.46 is nearly the +1.7 that the same
  # note calls a "raw-loop" figure and "a poor predictor of render behaviour
  # here". So this measurement is the one already known not to predict, and on it
  # the heaviest-reading loop of the four is the one that was left flat.
  #
  # The high end separates them even less. Relative to body:
  #
  #                    4-5.2k  5.2-6.2k   6.2-8k   8-11k   hand lp
  #   kembara_rindu     -22.5     -26.7    -29.5   -33.7      5600
  #   semua_untuk_mu    -24.5     -25.3    -25.4   -27.2      5200
  #   rauingar          -23.2     -25.8    -26.3   -27.2      6200
  #   lo_borges         -17.1     -18.8    -19.6   -21.8      6000
  #
  # semua_untuk_mu has the flatter top of the two and the lower lowpass;
  # rauingar and semua_untuk_mu are within 0.5 dB of each other everywhere and a
  # kilohertz apart. There is no ordering here to fit. Those four values are a
  # mix decision about how bright a bed sits under the arrangement, not a
  # reading off the source, and four points of taste cannot be regressed.
  #
  # So: lp is the middle of the range they actually chose (5200/5600/6000/6200)
  # and does not pretend to be measured.
  #
  # hp and sub_db get the light tier, and here there IS a reason rather than a
  # fit. The hp-90 tier exists for a record with "a kick and bass baked into" it.
  # These loops are the demucs sum with the drum stem dropped -- there is no kick
  # in them by construction, and 90 Hz sits above the fundamental of every bass
  # note up to F#2, so clearing at that height would take out the bass line these
  # were cut to provide. The one bump to 60/-3 is for a loop whose remaining low
  # end is genuinely forward.
  #
  # Every measurement is still recorded on the registry row. They are the numbers
  # somebody tuning one of these by hand would want, and they cost nothing to
  # keep now that they are not being asked to decide anything.
  DEFAULT_LP = 6000

  def voicing_for(path)
    low = mean(rms_series(path, filter: BANDS[:low], window: 0.25))
    body = mean(rms_series(path, filter: BANDS[:body], window: 0.25))
    air = mean(rms_series(path, filter: BANDS[:air], window: 0.25))
    return { hp: 45, sub_db: 0.0, lp: DEFAULT_LP } unless low && body

    low_vs_body = (low - body).round(2)
    hp, sub_db = low_vs_body > 0.0 ? [60, -3.0] : [45, 0.0]

    { hp:, sub_db:, lp: DEFAULT_LP,
      low_vs_body:, air_vs_body: air ? (air - body).round(2) : nil }
  end

  # Flat spelling, matching dilla.rb's PITCH_CLASSES and lib/key_lock.rb's note
  # on why: mixing Db with C# inside one rotation reads as two different keys on
  # paper even when it sounds like one. A local table rather than the global one
  # for the same reason KeyLock keeps its own -- this module does not reach into
  # the engine, the engine wires it.
  PITCH_CLASSES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

  def key_fields(path, key_probe)
    return {} unless key_probe

    pc, mode, fit = key_probe.call(path)
    return {} unless pc

    { key: "#{PITCH_CLASSES[pc]} #{mode}", key_pc: pc, key_mode: mode.to_s, key_fit: fit.round(3) }
  end

  # --- 6: registry ------------------------------------------------------------

  def registry
    return { "version" => 1, "loops" => [] } unless File.file?(REGISTRY)

    JSON.parse(File.read(REGISTRY))
  rescue JSON::ParserError => e
    warn "chop registry unreadable (#{e.message}) — treating as empty"
    { "version" => 1, "loops" => [] }
  end

  # Symbol-keyed and shaped exactly like a TRACK_SAMPLE_LOOPS literal, so the
  # merge in dilla.rb is a merge and not a translation layer. Entries whose wav
  # has gone missing are dropped here rather than at render time -- sample_loop_for
  # would silently return no bed, and a bed that quietly does not play is the
  # hardest kind of absence to notice.
  def registered_loops
    Array(registry["loops"]).filter_map do |loop|
      path = File.absolute_path?(loop["path"].to_s) ? loop["path"] : File.join(ROOT, loop["path"].to_s)
      next unless File.file?(path)

      [loop["slug"].to_s.to_sym,
       { path:, bpm: loop["bpm"].to_f, hp: loop["hp"].to_i,
         sub_db: loop["sub_db"].to_f, lp: loop["lp"].to_i }]
    end.to_h
  rescue StandardError => e
    warn "chop registry: #{e.message}"
    {}
  end

  # --- the pass ---------------------------------------------------------------

  # keep < candidates on purpose. The cheap scan proposes generously and the
  # expensive measurements dispose: separation is what makes the vocal-dominance
  # and key readings answerable, so the real rejections can only happen after it.
  def ingest!(src = DEFAULT_SOURCE, demucs:, deep:, key_probe: nil, label: nil,
              candidates: 16, keep: 8, span: 30.0, scratch: nil, fresh: false)
    raise "no such source: #{src}" unless File.file?(src)
    raise "demucs required — pip install demucs" if demucs.nil? || demucs.empty?

    slug_base = File.basename(src, ".*").downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_")[0, 24]
    # Under scratch/, never under samples/. Sixteen cuts through a 6-stem model
    # is ~300 MB of intermediate wav, and samples/ is a tracked directory --
    # left there it is one `git add -A` from the history.
    work = scratch || File.join(ROOT, "scratch", "chop_work")
    FileUtils.rm_rf(work) if fresh
    FileUtils.mkdir_p(work)

    puts "chop: scanning #{File.basename(src)}"
    proposed = propose(src, want: candidates, span:)
    raise "no candidate windows in #{src}" if proposed.empty?
    puts "chop: #{proposed.length} candidate windows " \
         "(#{proposed.map { |c| fmt_time(c[:start]) }.join(' ')})"

    # Named for the window they came from, in deciseconds, not for their position
    # in this run's candidate list. That is what makes the resume below safe:
    # cand_00 means nothing across two runs whose scans disagreed, while
    # cut_000310_0300 is the same thirty seconds of the same broadcast either
    # time, so reusing its stems cannot silently attach one window's separation
    # to another window's audio.
    cuts = proposed.map do |cand|
      dest = File.join(work, format("cut_%06d_%04d.wav", (cand[:start] * 10).round, (span * 10).round))
      unless File.file?(dest)
        run!("ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
             "-ss", cand[:start].round(3).to_s, "-t", span.round(3).to_s, "-i", src,
             "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest, label: "cut")
      end
      cand.merge(cut: dest)
    end

    puts "chop: demucs #{MODEL} over #{cuts.length} cuts " \
         "(#{(cuts.length * span).round}s) — keeping #{KEEP_STEMS.join('+')}, dropping #{DROP_STEMS.join('+')}"
    stem_dirs = separate!(cuts.map { |c| c[:cut] }, demucs:, out_dir: work)

    measured = cuts.filter_map { |cand| measure(cand, stem_dirs, deep:, key_probe:, span:) }
    raise "every candidate was rejected — nothing to register" if measured.empty?

    ranked = measured.sort_by { |m| -m[:score] }.first(keep)
    write_loops!(ranked, src:, slug_base:, label:, key_probe:)
  end

  # Everything that can only be asked once the drums and vocals are gone.
  def measure(cand, stem_dirs, deep:, key_probe:, span:)
    stem_dir = stem_dirs[cand[:cut]]
    return nil unless stem_dir && File.directory?(stem_dir)

    inst = instrumental!(stem_dir, File.join(stem_dir, "instrumental.wav"))
    return nil unless inst

    source_db = mean(rms_series(cand[:cut], window: 0.25))
    inst_db = mean(rms_series(inst, window: 0.25))
    return nil unless source_db && inst_db

    # What survived the separation, in dB relative to what went in. A presenter
    # over a jingle loses 10-plus dB here because most of what was there WAS the
    # presenter -- which is the honest signal that this window was talk, and it
    # is only available on this side of demucs.
    kept_db = (inst_db - source_db).round(2)
    return nil if kept_db < -12.0

    # What was taken out, measured against what was kept, one figure per dropped
    # stem. This is the evidence that the thing asked for actually happened: a
    # row claiming drums and vocals were removed, with no number saying how much
    # of either there was, is a claim rather than a result. Strongly negative is
    # the good case -- the removed material was loud and is now absent from the
    # sum. Near zero means demucs found as much drum or voice as everything else
    # put together, which is a window worth looking at by ear before using.
    dropped = DROP_STEMS.to_h do |stem|
      path = File.join(stem_dir, "#{stem}.wav")
      level = File.file?(path) ? mean(rms_series(path, window: 0.25)) : nil
      [stem, level ? (level - inst_db).round(2) : nil]
    end

    # Onsets off the raw cut, envelope and waveform off the instrumental: the
    # clock comes from the drums, the loop comes from what is left after they go.
    onsets = onsets_sec(cand[:cut], deep:)
    pcm = pcm_mono(inst)
    return nil if pcm.length < ANALYSIS_RATE

    trim = best_trim(pcm, envelope(inst), rate: ANALYSIS_RATE, onsets:, cut_sec: span)
    return nil unless trim

    cand.merge(
      instrumental: inst, bpm: trim[:bpm], kept_db:, dropped:,
      trim:,
      # Self-similarity leads, at a weight that puts its 0..1 range on the same
      # scale as the others: the question a sample bed has to answer is whether
      # the passage repeats, and everything else is a qualifier on a yes. Then
      # the scan's musicality, the rejoin cost, and how much of the record
      # survived separation.
      score: ((trim[:self_similarity] * 10.0) + cand[:musicality] -
              (trim[:cost] * 2.0) + (kept_db / 2.0)).round(3),
    )
  end

  def write_loops!(ranked, src:, slug_base:, label:, key_probe: nil)
    FileUtils.mkdir_p(DEST)
    # A shorter run must not leave the longer one's tail behind. Registry rows
    # for dropped slugs disappear, so a stale <slug>/loop.wav on disk would be a
    # sample nothing references and nothing cleans -- and if a later run reissued
    # that slug, TRACK=<slug> would resolve to whichever of the two was written
    # last.
    Dir.glob(File.join(DEST, "#{slug_base}_*")).each { |d| FileUtils.rm_rf(d) } # scan: intentional — this run's own output directories under DEST

    loops = ranked.each_with_index.map do |m, i|
      slug = format("%s_%02d", slug_base, i + 1)
      dir = File.join(DEST, slug)
      FileUtils.mkdir_p(dir)
      dest = File.join(dir, "loop.wav")
      # 16-bit rather than the f32 one hand-cut entry happens to be: this is the
      # end of the processing chain, not the middle of it, and the four tracked
      # loops are 0.9-3.7 MB each because they are committed alongside the code
      # that reads them.
      run!("ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
           "-ss", m[:trim][:start].to_s, "-t", m[:trim][:length].to_s, "-i", m[:instrumental],
           "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest, label: "loop trim")

      voicing = voicing_for(dest)
      {
        "slug" => slug,
        "path" => dest.sub("#{ROOT}/", ""),
        "bpm" => m[:bpm],
        "bars" => m[:trim][:bars],
        "hp" => voicing[:hp],
        "sub_db" => voicing[:sub_db],
        "lp" => voicing[:lp],
        "source" => src.sub("#{ROOT}/", ""),
        "source_label" => label || SOURCE_LABELS[File.basename(src, ".*")],
        "rights" => SOURCE_RIGHTS,
        "source_start_sec" => (m[:start] + m[:trim][:start]).round(3),
        "duration_sec" => m[:trim][:length],
        "self_similarity" => m[:trim][:self_similarity],
        "period_multiple" => m[:trim][:period_multiple],
        "rejoin_db" => m[:trim][:level_db],
        "kept_db" => m[:kept_db],
        # e.g. {"drums" => -21.4, "vocals" => -18.9} -- each removed stem's level
        # against the instrumental that replaced it.
        "dropped_db" => m[:dropped],
        "low_vs_body_db" => voicing[:low_vs_body],
        "air_vs_body_db" => voicing[:air_vs_body],
        "score" => m[:score],
        "stems_kept" => KEEP_STEMS,
        "stems_dropped" => DROP_STEMS,
        "model" => MODEL,
      }.merge(key_fields(dest, key_probe).transform_keys(&:to_s))
    end

    data = { "version" => 1, "ingested_at" => Time.now.utc.iso8601, "loops" => loops }
    DillaFrozen.write_json(REGISTRY, data)
    puts "chop: #{loops.length} loops -> #{REGISTRY.sub("#{ROOT}/", '')}"
    loops
  end

  def fmt_time(sec) = format("%d:%02d", sec.to_i / 60, sec.to_i % 60)
end
