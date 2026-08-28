# frozen_string_literal: true
#
# Sampled beds: the loop catalogue, chopping, cross-sampling and excitation.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Audio loops that play UNDERNEATH the synth arrangement. Deliberately not the
# stems path (use_stem_harmony), which REPLACES the harmonic bus wholesale --
# that swaps the engine's harmony out for the sample rather than putting the
# two together, which is the opposite of what a sampled bed is for. This is its
# own bus, mixed alongside drums/harm/bass like any other.
#
# Split in two since `chop` started producing entries of the same shape: the
# literal below is the hand-cut rack, every value in it argued for in the note
# above it, and TRACK_SAMPLE_LOOPS is that plus whatever the chopper has
# registered. Keeping the hand-cut set its own frozen constant means a bad
# ingest can never overwrite a measurement somebody reasoned their way to.
TRACK_SAMPLE_LOOPS_BUILTIN = {
  # The frozen 4-bar loop from the 92 BPM Ableton set recreated as :four_seven.
  # hp/sub_db are per-loop because the loops differ, and a global setting is
  # wrong for one of them whichever value it takes. Measured low-versus-mid,
  # untreated: four_seven -4.9 dB, nightbus -10.3 dB. The Malay loop has a kick
  # and bass baked into the record; nightbus does not, and highpassing it at 90
  # would take out low end it needs rather than low end that is in the way.
  kembara_rindu: { path: File.join(SAMPLE_DIR, "kembara_rindu", "loop.wav"), bpm: 92.0,
                   hp: 90, sub_db: -7.0, lp: 5600 },
  # 0:36 to 0:46. The operator gave 0:35-0:45 and then asked for the noise at
  # the front taken out; measured, the first second of that window is a thin
  # lead-in -- -27 dB overall and -41 dB below 500 Hz, against -16 once the
  # passage proper enters at 1.0s. Moving the window one second later starts at
  # full energy and reads slightly cleaner harmonically too (G minor fit 0.836
  # against 0.813). Still 10 seconds, still 4 bars at 96.
  #
  # Note for the next time this comes up: the complaint was "screaming", but
  # nothing in this window is bright -- the band above 3 kHz never rises above
  # -38 dB anywhere in it. What was audible as harsh was a quiet, thin entry,
  # not a loud one, so looking for high-frequency energy would have found
  # nothing and concluded there was no problem.
  #
  # Original note, still true of the boundary: the detector had picked
  # 13.88s off an energy step and was wrong: it found where the spoken
  # intro stopped, which is not the same thing as where the passage worth
  # sampling starts. The measurements side with the operator -- this section
  # reads G minor at a Krumhansl fit of 0.813, against 0.27 for the detector's
  # cut, on a clean chroma (G, then Bb / Ab / Eb / D / F, a G minor scale).
  #
  # 10 seconds is 4 bars at 96 BPM. It contains no onsets at all -- a sustained
  # melodic passage rather than a rhythmic loop -- which is why onset-based
  # tempo detection reports nothing for it, and why bar arithmetic against a
  # known-good boundary is the only honest way to get a tempo here.
  #
  # Low end left flat: see the note above, this one does not need correcting.
  # carries_own_harmony: Anuar Zain's record states its chords with voices, and
  # the first ten seconds are those voices and their backing and nothing else --
  # separated, only the vocals and `other` stems carry signal there, the rest
  # measuring -78 dB or lower. A generated progression on top is a second piece
  # of music in the same bar.
  #
  # render_dilla.rb's harmonic guard already argues exactly this ("there is no
  # case where you lay pads over a record and want a different key") but decides
  # it from whether the loop's key is READABLE. This loop reads Eb major at fit
  # 0.79 -- legible, so the guard concluded it could transpose the pads to match
  # and play them. Legibility is the wrong question for a record that has already
  # stated the chords; the right one is whether anything needs adding, and only
  # the crate knows that.
  #
  # Per record, not a mode. The other loops here want their progressions.
  semua_untuk_mu: { path: File.join(SAMPLE_DIR, "semua_untuk_mu", "loop.wav"), bpm: 96.0,
                    hp: 45, sub_db: 0.0, lp: 5200, carries_own_harmony: true },

  # 4 bars from 0.32s, where the music starts. The cleanest-looping source of
  # the three by a distance: self-similarity 0.654 against 0.300 for the next
  # best, tempo 114 at 61% on-grid against a 20% baseline, D major at 0.697.
  #
  # 114 rather than 120, decided by measurement rather than by preference. The
  # self-similarity peak sat at exactly 2.00s, which is one bar at 120 and not
  # at 114, so the two analyses disagreed. Looping each candidate and comparing
  # the last 100ms against the first settles it: 8.421s (114) rejoins itself at
  # -1.1 dB, 8.000s (120) at -8.6 dB. The 2.00s peak was a sub-bar repeat inside
  # the material, not the bar length -- worth remembering, because
  # self-similarity finds the shortest thing that repeats, which is not
  # necessarily the musical unit.
  #
  # hp/sub_db are provisional. Raw-loop measurement puts this at -6.6 dB
  # low-versus-mid, close to kembara_rindu's -5.9, which did need clearing --
  # but raw-loop numbers have already proved a poor predictor of render
  # behaviour here (semua_untuk_mu measures +1.7 raw and was the LEAST
  # problematic in a mix), so this is a starting point to check in a render
  # rather than a tuned value.
  lo_borges: { path: File.join(SAMPLE_DIR, "lo_borges", "loop.wav"), bpm: 114.0,
               hp: 60, sub_db: -3.0, lp: 6000 },

  # 2 bars at 92 BPM from one of the operator's own recordings, restored from
  # git history. Self-similarity picks 5.22s at 0.509, the clearest loop in
  # their own catalogue, and 92 is the tempo kembara_rindu already sits at.
  # C# minor at a Krumhansl fit of 0.70 -- the strongest reading of any of
  # their own tracks -- so it clears the harmonic guard comfortably.
  rauingar: { path: File.join(SAMPLE_DIR, "rauingar", "loop.wav"), bpm: 92.0,
              hp: 60, sub_db: -3.0, lp: 6200 },

  # Arat Swost Wolet, Ethiopian. 4 bars from 11.430s of the slowed copy.
  #
  # The de-vocaled stem, not the record: samples/arat_swost_wolet_slow.wav is
  # demucs's no_vocals output played at 0.8x, which the commit that added it does
  # not say and the audio does. Measured against the separated stems, on the
  # frames where the vocal sings the mix sits +4.90 dB above no_vocals and this
  # file sits -1.09 dB; on the frames where it is silent this file matches
  # no_vocals to +0.10 dB. So the singer is out, which is what makes it usable
  # as a bed under the engine's own harmony rather than a second tune.
  #
  # 84 BPM, decided by self-similarity rather than by onset spacing, which
  # disagreed. Onset gaps put it at 86.1; the repeat structure puts the bar at
  # 2.8575s and finds it again at 1, 2, 3, 4 and 5 bars -- five multiples of one
  # grid, which onset spacing cannot fake. 11.43s is 4 bars at 84. Its
  # self-repetition is 0.969, the cleanest in the rack by a distance (lo_borges,
  # previously the best, reads 0.654).
  #
  # A minor at a Krumhansl fit of 0.687, the strongest reading of anything here
  # except semua_untuk_mu.
  #
  # Known and not fixed: the loop does not rejoin cleanly. Its tail is about
  # 12 dB below its head, at EVERY candidate window on the grid, so it is the
  # phrase and not the cut -- the figure ends quiet. Expect an audible dip at
  # the seam and reach for LOOP_DELAY_BEATS or a crossfade if it matters. The
  # window at 11.430s was chosen because it has the best self-repetition and the
  # equal-best rejoin of the thirteen tried; bar 0 is within noise of it.
  #
  # hp/sub_db/lp are PROVISIONAL, in the same sense lo_borges's are and for the
  # same reason. Raw-loop bands, relative to the loudest: sub -0.7, low 0.0,
  # lomid -0.4, mid -8.0, hi -19.0, air -36.7. Low-versus-mid is +8.0 dB, which
  # is far more bass-forward than anything else in the rack (four_seven -4.9,
  # nightbus -10.3, lo_borges -6.6) -- this record brings a lot of its own low
  # end. But raw numbers have already proved a poor predictor of render
  # behaviour here, so these are a starting point to check in a render and not a
  # tuned value. The air figure is a cliff like four_seven's: there is nothing
  # above 8 kHz to recover with EQ, so SAMPLE_EXCITE is the knob for it.
  arat_swost_wolet: { path: File.join(SAMPLE_DIR, "arat_swost_wolet", "loop.wav"), bpm: 84.0,
                      hp: 90, sub_db: -6.0, lp: 6000 },
}.freeze

# The chopper's rack, merged in under the hand-cut one. Same shape, same bus,
# same per-loop hp/sub_db/lp fields -- a registered chop is a sample loop in
# every sense that matters here, selectable by name like any other:
#
#   ruby dilla.rb chop                       ingest samples/ubrukte_samples.mp3
#   TRACK=ubrukte_samples_03 ruby dilla.rb    render over that bed
#   CHOP_BED=1 ruby dilla.rb                  let the engine pick one by key
#
# BUILTIN wins a slug collision. Nothing generated should be able to take a name
# out from under an entry that was measured by hand.
TRACK_SAMPLE_LOOPS = RadioChop.registered_loops.merge(TRACK_SAMPLE_LOOPS_BUILTIN).freeze

# Hand-cut loops kept in the rack but deliberately kept OUT of the medley and
# the stream rotation. Still selectable by name (TRACK=rauingar), never
# chosen for you.
#
# This list exists so "no preset" can mean a decision rather than an oversight.
# Three of the four builtin loops had no preset and appeared in nothing the
# engine rendered on its own; that was an oversight, and nothing failed to say
# so. test_every_hand_cut_sample_loop_is_reachable_as_a_track_preset now holds
# the line, and reads this constant for the exceptions -- so leaving a loop out
# is one line here, and forgetting one is a test failure.
#
# rauingar: operator's call, 2026-08-07.
SAMPLE_LOOPS_OUT_OF_ROTATION = %i[rauingar].freeze

# The working names these two were ingested under, kept pointing at the same
# entries so anything already written against them keeps working. The song
# titles are the operator's; the old names were placeholders invented by the
# ingest (four_seven came off an Ableton set filename, nightbus was made up
# outright). kembara_rindu is the operator's best recollection rather than a
# verified title, so it is recorded as their attribution and not as fact.
TRACK_SAMPLE_LOOP_ALIASES = {
  four_seven: :kembara_rindu,
  nightbus: :semua_untuk_mu,
  # dmaj_open was a placeholder for a sample the operator had not yet named.
  dmaj_open: :lo_borges,
  # Sheger. The chopper slugs its output after the source FILE, and the file
  # was called ubrukte_samples.mp3 -- "unused samples", a working name for a
  # crate, not the name of the record. Eight chops came out of it and all eight
  # were carrying the filename. Same correction as four_seven -> kembara_rindu
  # above, and the reason is the same: the ingest invents a slug, the operator
  # knows what the record is.
  sheger_01: :ubrukte_samples_01,
  sheger_02: :ubrukte_samples_02,
  sheger_03: :ubrukte_samples_03,
  sheger_04: :ubrukte_samples_04,
  sheger_05: :ubrukte_samples_05,
  sheger_06: :ubrukte_samples_06,
  sheger_07: :ubrukte_samples_07,
  sheger_08: :ubrukte_samples_08,
}.freeze

# --- cross-sample processing ---------------------------------------------------
#
# Two records treated as one instrument. Both of these produce something neither
# loop can give on its own, which is the reason to prefer them over another
# effect applied to a single source.
#
#   DILLA_XCONVOLVE=1  one loop becomes the room the other is played in
#   DILLA_XGATE=1      one loop's harmony, the other's rhythm
#
# DILLA_XSAMPLE names the partner track (any key of TRACK_SAMPLE_LOOPS).
DILLA_XCONVOLVE = ENV["DILLA_XCONVOLVE"] == "1"
DILLA_XGATE = ENV["DILLA_XGATE"] == "1"
# Kept short on purpose. A long impulse convolves the partner's whole melody
# into the source and the result is mush; ~1s reads as a space rather than as a
# second tune.
XCONV_IR_SEC = (ENV["DILLA_XCONV_IR_SEC"] || 1.0).to_f.clamp(0.1, 4.0)
XCONV_WET = (ENV["DILLA_XCONV_WET"] || 0.62).to_f.clamp(0.0, 1.0)
# The envelope follower's smoothing. Too fast and it transfers individual
# waveform cycles, which is ring modulation, not gating.
XGATE_SMOOTH_HZ = (ENV["DILLA_XGATE_SMOOTH_HZ"] || 24).to_i
XGATE_FLOOR = (ENV["DILLA_XGATE_FLOOR"] || 0.18).to_f.clamp(0.0, 1.0)

def cross_sample_partner_path(self_track)
  name = ENV["DILLA_XSAMPLE"].to_s.strip
  return nil if name.empty?

  key = name.downcase.tr("-", "_").to_sym
  return nil if key.to_s == self_track.to_s.downcase.tr("-", "_")

  path = TRACK_SAMPLE_LOOPS.dig(key, :path)
  path if path && File.file?(path)
end

# Builds a short impulse response from the partner: trimmed, banded, and decayed
# so it does not ring forever. Deliberately NOT loudnorm'd -- afir's own irnorm
# then fights it, and the level is fixed by measurement after the convolution
# instead, where it can be matched to the actual source.
def cross_sample_impulse!(partner, dest)
  sh! "ffmpeg", "-y", "-t", XCONV_IR_SEC.to_s, "-i", partner,
      "-af", "highpass=f=90,lowpass=f=9000," \
             "afade=t=out:st=#{(XCONV_IR_SEC * 0.35).round(3)}:d=#{(XCONV_IR_SEC * 0.65).round(3)}",
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest
  dest
end

# Convolution output level depends entirely on the impulse's energy, which
# varies per sample pair, so no fixed gain is right. Measured on this pair:
# irnorm=1 landed at -62 dB against a -20 dB source (inaudible) and irnorm=0 at
# -0.2 dB (clipping). So convolve unnormalised, which is at least predictable,
# then match the source by measurement -- the same measure-then-gain the vocal
# cleaner uses for the same reason.
def cross_sample_convolve!(loop_path, partner, dest)
  ir = "#{dest}.ir.wav"
  cross_sample_impulse!(partner, ir)
  raw = "#{dest}.raw.wav"
  sh! "ffmpeg", "-y", "-i", loop_path, "-i", ir,
      "-filter_complex",
      "[0:a][1:a]afir=dry=#{(1.0 - XCONV_WET).round(3)}:wet=#{XCONV_WET}:" \
      "maxir=#{XCONV_IR_SEC}:irnorm=0[c];" \
      "[c]highpass=f=45[out]",
      "-map", "[out]", "-ar", SAMPLE_RATE.to_s, "-ac", "2",
      "-c:a", "pcm_s16le", raw

  want = band_rms(loop_path, highpass: 20, lowpass: 20_000) rescue nil
  got = band_rms(raw, highpass: 20, lowpass: 20_000) rescue nil
  trim = if want&.finite? && got&.finite?
           (want - got).clamp(-48.0, 24.0)
         else
           0.0
         end
  sh! "ffmpeg", "-y", "-i", raw,
      "-af", "volume=#{trim.round(2)}dB,alimiter=limit=0.95:level_out=0.96",
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest
  dmesg("cross-sample convolve: matched #{got&.round(1)}dB → #{want&.round(1)}dB (#{trim.round(1)}dB)",
        unit: "xsmp0", parent: "dilla0")
  FileUtils.rm_f([ir, raw])
  dest
end

# The source's harmony driven by the partner's rhythm. amultiply rather than
# sidechaingate: a gate is a switch and leaves the source's own attacks intact
# between openings, while multiplying by a rectified, smoothed envelope makes
# the partner's shape the ONLY amplitude contour the result has.
def cross_sample_gate!(loop_path, partner, dest, duration:)
  env_path = "#{dest}.env.wav"
  # Rectify and smooth into a control signal, floored so the source never fully
  # disappears in the partner's gaps.
  sh! "ffmpeg", "-y", "-i", partner,
      "-af", "highpass=f=60,lowpass=f=8000,aeval=abs(val(0))|abs(val(1))," \
             "lowpass=f=#{XGATE_SMOOTH_HZ}," \
             "volume=#{(1.0 - XGATE_FLOOR).round(3)}," \
             "aeval=val(0)+#{XGATE_FLOOR}|val(1)+#{XGATE_FLOOR}," \
             "atrim=0:#{duration},apad=whole_dur=#{duration}",
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", env_path
  sh! "ffmpeg", "-y", "-i", loop_path, "-i", env_path,
      "-filter_complex",
      "[0:a]atrim=0:#{duration},apad=whole_dur=#{duration}[src];" \
      "[src][1:a]amultiply,alimiter=limit=0.95:level_out=0.96[out]",
      "-map", "[out]", "-ar", SAMPLE_RATE.to_s, "-ac", "2",
      "-c:a", "pcm_s16le", dest
  FileUtils.rm_f(env_path)
  dest
end

def cross_sample_process(track, loop_path)
  # Morph first, cross-sample second: convolving a loop that has already been
  # turned into a chord gives the partner's room to the whole chord, which is
  # what you want; doing it the other way convolves the room itself into every
  # transposed copy and smears twice.
  if SAMPLE_FM || SAMPLE_SCALE
    morphed = sample_morph!(loop_path, File.join(Dir.tmpdir, "dilla_morph_#{Process.pid}.wav"))
    loop_path = morphed if morphed && File.file?(morphed)
  end
  return loop_path unless DILLA_XCONVOLVE || DILLA_XGATE

  partner = cross_sample_partner_path(track)
  unless partner
    warn "cross-sample: DILLA_XSAMPLE=#{ENV['DILLA_XSAMPLE'].inspect} is not another track's loop — skipping"
    return loop_path
  end

  out = loop_path
  begin
    if DILLA_XCONVOLVE
      dest = File.join(Dir.tmpdir, "dilla_xconv_#{Process.pid}.wav")
      out = cross_sample_convolve!(out, partner, dest)
      puts "cross-sample: convolved with #{File.basename(File.dirname(partner))} " \
           "(#{XCONV_IR_SEC}s impulse, wet #{XCONV_WET})"
    end
    if DILLA_XGATE
      dest = File.join(Dir.tmpdir, "dilla_xgate_#{Process.pid}.wav")
      len = audio_duration_sec(out).to_f
      out = cross_sample_gate!(out, partner, dest, duration: len.positive? ? len.round(3) : 8.0)
      puts "cross-sample: amplitude taken from #{File.basename(File.dirname(partner))} " \
           "(floor #{XGATE_FLOOR})"
    end
    out
  rescue StandardError => e
    warn "cross-sample: #{e.class} — #{e.message}; using the plain loop"
    loop_path
  end
end

# Is the sample bed itself short of low end, rather than the mix that used it?
#
# Measured on the raw SAMPLE_LOOP file, not on the processed bed: the question
# is what the source had, and cross_sample_process is both expensive and beside
# the point. Memoised per path — the quality gate asks once per take.
#
# Returns false when there is no sample bed at all, so an ordinary render is
# judged exactly as before.
def sample_bed_band_limited?(threshold = -9.0)
  raw = ENV["SAMPLE_LOOP"].to_s
  return false if raw.empty? || raw == "0" || !File.file?(raw)

  @sample_bed_delta ||= {}
  delta = @sample_bed_delta[raw] ||= begin
    DillaMaster.sub_kick_balance(render_spectrum(raw))[:low_mid_delta].to_f
  rescue StandardError => e
    warn "sample bed probe: #{e.class} — treating bed as full-range"
    0.0
  end

  limited = delta < threshold
  if limited && !@sample_bed_warned
    @sample_bed_warned = true
    warn "quality gate: sample bed #{File.basename(raw)} is band-limited " \
         "(low-mid #{delta.round(2)} dB) — sub deficit attributed to the source, not the mix"
  end
  limited
end

# SAMPLE_LOOP is a PATH, and "1" is not one.
#
# The variable names a specific file to use as the bed; empty means "look one up
# for this track". It reads like a switch, so it gets set like a switch, and
# SAMPLE_LOOP=1 sends it looking for a file called "1". That file does not
# exist, File.file? says so, and the method returns nil -- no bed, no warning,
# a track that renders perfectly and contains no sample at all.
#
# Thirteen beats were rendered that way before anyone noticed, every one of them
# with the flag set to turn samples ON.
#
# The truthy words now mean what everybody assumes they mean.
SAMPLE_LOOP_ON = %w[1 true yes on].freeze

# Which loop a track would use, WITHOUT processing it.
#
# Split out of sample_loop_for so the tempo can ask which record is going under
# the beat before deciding what tempo the beat is. sample_loop_for morphs and
# convolves on the way out, which is far too expensive to run from resolve_bpm
# and would recurse besides.
def sample_loop_entry(track)
  raw = ENV["SAMPLE_LOOP"].to_s.strip
  return if raw == "0"

  raw = "" if SAMPLE_LOOP_ON.include?(raw.downcase)
  unless raw.empty?
    # A slug, not only a path. SAMPLE_LOOP took a bare filename, so choosing a
    # known bed by hand meant passing its path and silently losing the hp/sub_db/
    # lp that TRACK_SAMPLE_LOOPS records for it -- and those are measured per
    # loop precisely because a global value is wrong for one of them whichever
    # way it goes (four_seven -4.9 dB against nightbus -10.3 dB, per that table).
    #
    # This is what lets a bed and a progression be chosen independently:
    # SAMPLE_LOOP picks the sample, TRACK still picks the chords. Before, both
    # came off TRACK, so a Dilla progression under the semua bed was not
    # expressible.
    slug = raw.downcase.tr("-", "_").to_sym
    named = TRACK_SAMPLE_LOOPS[TRACK_SAMPLE_LOOP_ALIASES.fetch(slug, slug)]
    return named if named

    return { path: raw, bpm: ENV.fetch("SAMPLE_LOOP_BPM", "0").to_f }
  end

  key = track.to_s.downcase.tr("-", "_").to_sym
  TRACK_SAMPLE_LOOPS[TRACK_SAMPLE_LOOP_ALIASES.fetch(key, key)] || chopped_bed_for(track)
end

def sample_loop_for(track)
  entry = sample_loop_entry(track)
  return unless entry && File.file?(entry[:path].to_s)

  # Memoised: sample_loop_for is called from several places in one render, and
  # each call would otherwise re-run the morph and the convolution.
  @cross_sample_cache ||= {}
  key = [track.to_s, entry[:path]]
  @cross_sample_cache[key] ||= cross_sample_process(track, entry[:path])
  entry.merge(path: @cross_sample_cache[key])
end

# The chopper's rack as a fallback bed for tracks that have no loop of their own.
#
# Off by default (CHOP_BED=1). Most of the rotation was written without a sampled
# bed under it, and switching one on for every track that lacks one is a change
# to the sound of the whole catalogue, not a feature.
#
# Chosen by key rather than at random, which is the only way this is any use.
# KEY_LOCK already transposes every progression to one tonic -- Bb by default --
# so the pads land in a known key on every render, and a bed in a different one
# is a bed fighting the arrangement. Loops carry their measured pitch class from
# ingest, so the match is a lookup rather than another analysis pass.
#
# Deterministic on the track name, not on rand: the same track has to get the
# same bed twice in a row or nothing downstream is reproducible.
def chopped_bed_for(track)
  return if ENV.fetch("CHOP_BED", "0") == "0"

  # Memoised per track for the same reason sample_loop_for memoises its own
  # processing: it is called from several places in one render, and without this
  # the pick is re-derived and re-announced four times a take.
  @chopped_bed_cache ||= {}
  return @chopped_bed_cache[track.to_s] if @chopped_bed_cache.key?(track.to_s)

  @chopped_bed_cache[track.to_s] = chopped_bed_pick(track)
end

def chopped_bed_pick(track)
  rack = RadioChop.registered_loops
  return if rack.empty?

  meta = Array(RadioChop.registry["loops"]).select { |l| rack.key?(l["slug"].to_s.to_sym) }
  wanted = KeyLock.enabled? ? KeyLock.pitch_class(KeyLock.target) : nil
  in_key = wanted ? meta.select { |l| l["key_pc"] == wanted } : []
  # Falling back to every loop rather than to none: an out-of-key bed is a
  # compromise, no bed at all when CHOP_BED was asked for is a dead switch.
  pool = in_key.empty? ? meta : in_key
  return if pool.empty?

  pool = pool.sort_by { |l| [-l["score"].to_f, l["slug"].to_s] }
  pick = pool[track.to_s.sum % pool.length]
  entry = rack[pick["slug"].to_s.to_sym]
  return unless entry

  dmesg("chop bed: #{pick['slug']} #{pick['key'] || '?'} @#{pick['bpm']} " \
        "#{in_key.empty? ? '(no key match)' : '(key-locked)'}", unit: "chop0", parent: "dilla0")
  entry
end

# --- sample loop excitation ---------------------------------------------------
#
# Measured on the two registered loops (mono, 44.1k, banded against each one's
# own loudest band):
#
#   four_seven   sub -4.0  low +0.0  lomid -6.9  mid -15.6  hi -39.9  air -52.7
#   semua 35-45  sub -7.3  low +0.0  lomid -9.5  mid -20.0  hi -32.6  air -33.7
#
# four_seven's -39.9/-52.7 is a cliff, not a rolloff: there is essentially no
# content above 3 kHz. That matters because the only high-frequency stage in
# this filter is a LOWPASS at 11 kHz -- it has nothing to remove, and no stage
# anywhere in the sample path puts anything back. An EQ shelf cannot help
# either; you cannot boost what is not there.
#
# The content has to be synthesised from the harmonics of what IS present,
# which is what an exciter does: split the signal, drive one copy into a
# non-linearity, high-pass the result so only the newly generated harmonics
# survive, and blend that under the dry. (Aural Exciter / parallel saturation;
# see Sound On Sound on restoring HF in pitch-shifted samples.)
#
# Character picks which harmonics get generated, and it is the "older or more
# modern" dial:
#   even  x + k*x*|x|   2nd/3rd order, tube and transformer bloom -- rounder,
#                       sits behind the beat, reads as older.
#   odd   tanh(d*x)     odd-order, console and transistor clipping -- harder
#                       and more present, reads as modern.
#
# Off by default: it changes the sound of every registered loop, and the right
# amount is per-sample. SAMPLE_EXCITE=0.3 is a sensible starting point for
# four_seven; a sample that already has air needs far less or none.
SAMPLE_EXCITE_MIX = (ENV["SAMPLE_EXCITE"] || "0").to_f.clamp(0.0, 1.0)
SAMPLE_EXCITE_HZ = (ENV["SAMPLE_EXCITE_HZ"] || "2200").to_f
SAMPLE_EXCITE_DRIVE = (ENV["SAMPLE_EXCITE_DRIVE"] || "1.8").to_f.clamp(1.0, 20.0)
SAMPLE_EXCITE_CHARACTER = (ENV["SAMPLE_EXCITE_CHARACTER"] || "even").to_s.downcase

def sample_excite_shaper
  unless SAMPLE_EXCITE_CHARACTER.start_with?("odd")
    k = (SAMPLE_EXCITE_DRIVE * 0.06).round(4)
    return "aeval=exprs='val(0)+#{k}*val(0)*abs(val(0))|val(1)+#{k}*val(1)*abs(val(1))'"
  end

  n = Math.tanh(SAMPLE_EXCITE_DRIVE).round(6)
  "aeval=exprs='tanh(#{SAMPLE_EXCITE_DRIVE}*val(0))/#{n}|tanh(#{SAMPLE_EXCITE_DRIVE}*val(1))/#{n}'"
end

def build_sample_loop_filter(idx, duration, loop_bpm, target_bpm)
  # Looked up first because the per-loop defaults below all read from it. It was
  # assigned further down and referenced up here, which in Ruby is nil rather
  # than an error -- so the per-loop settings would have been silently ignored
  # instead of failing loudly.
  entry = sample_loop_for(ENV["TRACK"]) || {}

  # Tempo-match rather than resample: the loop was warped in the DAW at its own
  # BPM, so play it at the render's tempo instead of letting it drift.
  ratio = loop_bpm.to_f.positive? ? (target_bpm / loop_bpm).clamp(0.5, 2.0) : 1.0

  # Varispeed: pitch follows speed, the way a record does.
  #
  # atempo holds pitch while changing tempo, which is the modern, correct-sounding
  # option and is not what these records did. Slowing a sample on an MPC or a
  # turntable drops its pitch with it -- that is where the thickness comes from,
  # and why a sped-up sample sounds thin no matter how it is EQ'd. asetrate then
  # aresample reproduces it exactly, and the bar grid still lines up, because
  # playing a 4-bar loop at ratio r gives 4 bars at r times the tempo either way.
  #
  # SAMPLE_LOOP_SEMITONES pitches further WITHOUT changing tempo, for when the
  # tempo is already where it should be and only the weight is missing. It is
  # applied as an extra resample and undone with atempo, so the two controls stay
  # independent: one moves both, the other moves only pitch.
  # Varispeed on by default. Holding a sample's pitch while slowing it is the
  # modern-sounding choice and the wrong one here: these records were slowed on
  # a sampler, pitch fell with speed, and that fall is where the weight is.
  varispeed = ENV.fetch("SAMPLE_LOOP_VARISPEED", entry[:varispeed] == false ? "0" : "1") != "0"
  extra_semis = ENV.fetch("SAMPLE_LOOP_SEMITONES", "0").to_f.clamp(-12.0, 12.0)

  tempo = if (ratio - 1.0).abs < 0.001
            ""
          elsif varispeed
            # Say how far the pitch actually moved. BPM_SCALE defaults to 0.96,
            # which pulls samples down about 0.71 semitones — a real transposition
            # that nothing in the output ever mentioned, so it read as "the tracks
            # sound lower" without a number attached to it. It also means a key
            # lock cannot be checked by ear against a sampled bed unless you know
            # this figure. Reported, not changed: pitch falling with speed is the
            # point, per the note above.
            semis = 12.0 * Math.log2(ratio)
            if semis.abs > 0.05
              dmesg(format("varispeed: samples %+.2f semitones (ratio %.4f)", semis, ratio),
                    unit: "smpl0", parent: "dilla0")
            end
            "asetrate=#{(SAMPLE_RATE * ratio).round},aresample=#{SAMPLE_RATE},"
          else
            "atempo=#{ratio.round(5)},"
          end

  unless extra_semis.zero?
    shift = 2.0**(extra_semis / 12.0)
    # Resample moves pitch and length together; atempo puts the length back.
    comp = 1.0 / shift
    stages = []
    stages << 2.0 while comp / stages.inject(1.0, :*) > 2.0
    stages << 0.5 while comp / stages.inject(1.0, :*) < 0.5
    stages << (comp / stages.inject(1.0, :*))
    tempo += "asetrate=#{(SAMPLE_RATE * shift).round},aresample=#{SAMPLE_RATE}," +
             stages.map { |s| "atempo=#{s.round(6)}" }.join(",") + ","
  end
  vol = ENV.fetch("SAMPLE_LOOP_VOL", "0.8").to_f
  # A sampled record arrives with its own kick and bass already in it, and until
  # now nothing here could reach them: the highpass was a hardcoded 45 and there
  # was no shelf. Measured on four_seven with normalisation off, muting the
  # engine's kick moved the 40-100 Hz band by 0.0 dB and muting the synth bass
  # by 0.0 dB, while muting the loop moved it by -4.0 dB. The loop was the whole
  # low end -- which is why turning KICK_GAIN down never fixed a low end that
  # was too loud, across three attempts.
  # Per-loop defaults from TRACK_SAMPLE_LOOPS; env still wins when pinned.
  hp = (ENV["SAMPLE_LOOP_HP"] || entry[:hp] || 45).to_i
  sub_db = (ENV["SAMPLE_LOOP_SUB_DB"] || entry[:sub_db] || 0).to_f
  sub_eq = sub_db.zero? ? "" : "equalizer=f=90:t=o:w=1.1:g=#{sub_db},"
  # Wow on the LOOP only, never the kit. A sampled record has tape or vinyl
  # instability in it and a drum machine does not; modulating both together
  # sounds like the whole mix is unstable, while modulating only the sample
  # sounds like the sample came off a record. Two slow rates rather than one so
  # it does not tick.
# LOOP_WOW is disabled here rather than left in place looking functional.
#
# It was built on vibrato, which is transparent in this ffmpeg build: depths
# of 0.1, 0.5 and 0.9 all produce output identical to the input. A switch that
# reports a value and changes nothing is worse than one that is absent,
# because it silently absorbs the attempt to use it.
#
# A working implementation already exists in lib/tape_hysteresis.rb --
# Ornstein-Uhlenbeck drift driving a fractional-delay read, in Ruby, verified.
# Reach for TAPE_WOW_MS instead, which applies it to the master.
wow = ""
if ENV["LOOP_WOW_CENTS"].to_f.positive?
  warn "LOOP_WOW_CENTS: vibrato is transparent in this ffmpeg build — use TAPE_WOW_MS"
end

  # Tempo-synced delay on the loop. Dotted-8th is 3/16 of a bar and is the
  # figure that reads as hip-hop rather than as an effect: at 92 BPM that is
  # 489ms. Feedback stays low because the loop is already repeating -- a long
  # tail on a repeating source turns into mud within two bars.
  echo_beats = ENV.fetch("LOOP_DELAY_BEATS", "0").to_f
  echo = if echo_beats.positive? && target_bpm.to_f.positive?
           ms = ((60.0 / target_bpm) * echo_beats * 1000).round
           "aecho=0.8:#{ENV.fetch('LOOP_DELAY_MIX', '0.32')}:#{ms}:" \
             "#{ENV.fetch('LOOP_DELAY_FEEDBACK', '0.28')},"
         else
           ""
         end

  # sample_modern_chain is the addition that matches sonitex_enabled? turning
  # Sonitex off for a sampled bed: denoise / air / sub / width on the LOOP,
  # not the master. SAMPLE_MODERN=0 keeps the old subtraction-only path.
  modern = sample_modern_chain
  modern_s = modern && !modern.empty? ? "#{modern}," : ""
  # The sampled bed gets the shaping the pad bus gets, or it stays a bed.
  #
  # build_harm_bus_filter lifts body, mid, presence and air into the chords --
  # four additive stages plus a sub cut -- and the loop chain had none of them.
  # Everything above this line is subtractive: a highpass, a mud cut and a
  # lowpass. A sample run through only those cannot sit beside a pad that has
  # been lifted in four bands; it reads as something playing behind the track
  # rather than an instrument in it, which is the whole difference between a
  # loop and a voice.
  #
  # Every default here is 0.0, so a render that does not ask for them is the
  # render it was before. SAMPLE_LOOP_VOL (0.8 against the harm bus's 1.68) and
  # SAMPLE_LOOP_WEIGHT (0.9 against 1.52) are the other half of the gap and are
  # already knobs; these are the half that had no control at all.
  #
  # Centres match the harm bus rather than being picked fresh: 220 Hz body,
  # 900 Hz mid, 2.8 kHz presence, 6 kHz air. Sharing centres is what lets the
  # two buses be balanced against each other by ear instead of fighting in
  # different bands.
  body_g = ENV.fetch("SAMPLE_LOOP_BODY_DB", "0").to_f
  mid_g = ENV.fetch("SAMPLE_LOOP_MID_DB", "0").to_f
  pres_g = ENV.fetch("SAMPLE_LOOP_PRESENCE_DB", "0").to_f
  air_g = ENV.fetch("SAMPLE_LOOP_AIR_DB", "0").to_f
  shape = +""
  shape << "equalizer=f=220:t=o:w=1.2:g=#{body_g}," unless body_g.zero?
  shape << "equalizer=f=900:t=o:w=1.4:g=#{mid_g}," unless mid_g.zero?
  shape << "equalizer=f=2800:t=h:w=1800:g=#{pres_g}," unless pres_g.zero?
  shape << "equalizer=f=6000:t=h:w=2800:g=#{air_g}," unless air_g.zero?

  common = "aformat=channel_layouts=stereo,#{tempo}volume=#{vol}," \
           "#{wow}#{echo}#{modern_s}" \
           "highpass=f=#{hp}," \
           "#{sub_eq}" \
           "equalizer=f=300:t=o:w=1.4:g=#{ENV.fetch('SAMPLE_LOOP_MUD_DB', '-2.0')}," \
           "#{shape}" \
           "lowpass=f=#{(ENV['SAMPLE_LOOP_LP'] || entry[:lp] || 11_000).to_i}"
  tail = "atrim=0:#{duration},apad=whole_dur=#{duration},asetpts=PTS-STARTPTS"

  return "[#{idx}:a]#{common},#{tail}[loopbed]" if SAMPLE_EXCITE_MIX <= 0.0

  # The high-pass on the wet branch is the whole trick: it discards the band
  # the dry signal already covers and keeps only the harmonics the shaper
  # invented above it, so this adds air instead of adding distortion.
  #
  # The blend level rides on the wet branch as a `volume`, NOT as amix
  # `weights`: the weights value is space-separated ("1 0.3") and a bare space
  # inside a filtergraph does not survive parsing, so the weights were dropped
  # and both branches summed at unity. Measured, that raised the low band by
  # the same 2.4 dB as the air band -- a broadband level increase wearing an
  # exciter's clothes. With the gain on the branch instead, the low band moves
  # 0.0 dB and only 3 kHz upward changes, which is the entire point.
  #
  # normalize=0 stops amix halving the dry level to make headroom.
  "[#{idx}:a]#{common},asplit=2[lpdry#{idx}][lpwet#{idx}];" \
    "[lpwet#{idx}]#{sample_excite_shaper},highpass=f=#{SAMPLE_EXCITE_HZ.round}:poles=2," \
    "volume=#{SAMPLE_EXCITE_MIX.round(3)}[lpexc#{idx}];" \
    "[lpdry#{idx}][lpexc#{idx}]amix=inputs=2:normalize=0," \
    "#{tail}[loopbed]"
end
