# frozen_string_literal: true
#
# The master bus: console emulation, width, true-peak guard, loudness.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# The console and the mastering desk, in that order, before the loudness stage.
#
# The master bus ran loudnorm into a limiter and nothing else: correct levels,
# no character. Everything below is copied from documented practice rather than
# invented, and each stage names its source.
#
# 1. TRANSFORMER BUMP. Seventies Neve desks mixed at roughly microphone level
#    and brought the signal back up through output transformers. Transformers
#    are not flat: the core adds a small lift in the low bass and rolls away the
#    top. Both are reproduced here, gently, because the effect on a real
#    desk is small and the temptation to overdo it is what makes emulations
#    sound like emulations.
#
# 2. VOLTAGE-MIXING NONLINEARITY. The "harmonic magic" of the 80-series is
#    discrete class-A stages departing slightly from linear as they are pushed.
#    A soft clipper at low drive is the honest version. Oversampled four times,
#    or the harmonics it creates fold back down the spectrum as aliasing, which
#    is the one artefact analog cannot produce.
#
# 3. TRIODE HARMONICS. Crane Song's HEDD offers triode, pentode and tape.
#    Triode adds the even-order harmonics of a single-ended tube stage -- the
#    octave, which the ear hears as warmth rather than distortion. aexciter's
#    blend control sets the balance between second and third harmonic, so a
#    negative blend is the triode setting and a positive one the pentode.
#
# 4. THE STC-8, TEMPO-LOCKED. This is the specific thing Dave Cooley did to
#    Donuts: he timed the compressor's release to each track's tempo, to keep
#    the pump disorienting instead of smoothing it out. Release here is an
#    eighth note at the track's own BPM, so the bus recovers exactly as the next
#    off-beat lands and the pump becomes part of the rhythm.
#
# 5. MATTE TOP. Cooley used a GML equalizer for top end and said he was not
#    after a slick top at the time -- a "matte" finish. A matte top is a WIDE,
#    low shelf placed high, which lifts air without putting an edge on any one
#    band. A narrow boost is the slick sound he was avoiding.
#
# All five are built in outboard.rb and reached through Outboard.chain below.
# Two constants naming the transformer's corner frequencies lived here until
# 2026-08-12, left behind when the stage moved into the rack; the rack carries
# its own, so these described the sound rather than setting it.

def console_master_chain(cfg)
  return nil if ENV["CONSOLE"] == "0"

  rack = ENV.fetch("RACK", Outboard::DEFAULT_RACK).to_sym
  unless Outboard::RACKS.key?(rack)
    warn "rack: no such rack #{rack.inspect} — using #{Outboard::DEFAULT_RACK}. " \
         "Choices: #{Outboard::RACKS.keys.join(', ')}"
    rack = Outboard::DEFAULT_RACK
  end
  # A unit named in a rack but not built would vanish silently and the rack
  # would quietly become a shorter rack. Say so instead.
  Outboard.chain(rack, bpm: cfg[:bpm].to_f,
                       missing: ->(unit) { warn "rack #{rack}: no unit named #{unit.inspect} — skipped" })
end

# No loudnorm in the graph. This is the fix for a track whose level wanders.
#
# ffmpeg's loudnorm has two modes and picks between them silently. Given
# measured values from a first pass it applies ONE static gain -- transparent,
# which is what mastering means. Given none, as here, it falls back to DYNAMIC
# normalisation: it rides the gain continuously through the track, pushing quiet
# passages up and pulling loud ones down, second by second. It hits the target
# LUFS beautifully and it destroys the arrangement, because every decision about
# what should be loud gets overruled by a meter.
#
# That is what "the overall volume changes all the time" was. Every loudnorm in
# this engine was the single-pass kind.
#
# So the graph now ends at the limiter, and the levelling happens afterwards in
# normalise_master!, which measures the finished file and applies one number.
def true_peak_guard_for_style(input_tag, cfg, out_tag: "out")
  # Console before the limiter. Saturation changes both peak and loudness, so
  # colouring after measuring would hand back a track that no longer hits the
  # target it was measured against.
  console = console_master_chain(cfg)
  head = "[#{input_tag}]#{console ? "#{console}," : ''}"
  "#{head}aresample=#{SAMPLE_RATE}," \
    "alimiter=limit=#{TRUE_PEAK_CEILING_LINEAR}:attack=1:release=40:level=disabled[#{out_tag}]"
end

# Measures the finished track and applies a single gain to it.
#
# This is the second pass that loudnorm needed and never got. Nothing here moves
# during the track: one measurement, one number, one limiter to catch whatever
# the gain pushes over the ceiling. A section that was written quiet stays quiet
# relative to the rest, which is the whole point of writing it quiet.
# Width at the master, because that is the only place it can be verified.
#
# Measured: finished tracks sit at -45 to -65 dB side-to-mid where real records
# are -3 to -6. The harmonic bus is not the cause -- it measures -6.8 on its own,
# with or without a stereo sample bed under it. The drum bus is mono because
# every one-shot in the kit is a single-channel file, and it is 27 dB louder
# than the harmonic bus, so it dominates the sum.
#
# Two fixes were tried at the source and neither survived into a render. Widening
# the drum bus moved the finished file 0.3 dB (-48.3 to -48.6 with the switch on
# and off, which is nothing). Lifting the harmonic bus 20.6 dB moved it 2.2 dB.
# Both worked in isolation and neither worked in place, which means the loss is
# somewhere in the summing I have not found.
#
# So this runs last, on the file itself, where the number can be checked against
# the file that ships rather than against a stage in the middle. Above 300 Hz
# only, so the kick and bass stay centred and mono_bass has nothing to undo.
MASTER_WIDTH_HZ = 300

def master_width
  ENV.fetch("MASTER_WIDTH", "0").to_f.clamp(0.0, 1.0)
end

def widen_master!(path)
  amt = master_width
  return path unless amt.positive? && File.file?(path)

  # Phase-coherent widening, not Haas. Measured 2026-08-13.
  #
  # This used haas=left_delay=(2.0+5.0*amt):right_delay=(0.5+1.2*amt). At the
  # MASTER_WIDTH=0.5 these renders were made with, that is 4.5 ms against 1.1 ms
  # — a 3.4 ms inter-channel delay, which is a comb filter with nulls at roughly
  # 147, 441 and 735 Hz. The finished tracks measured a SIDE channel LOUDER than
  # their MID (dilla_semua_96 at +1.7 dB) and lost 7.5 dB summing to mono, with
  # the loss concentrated in 150-800 Hz. Predicted nulls and measured band agree.
  #
  # Source material is not the cause: samples/semua_untuk_mu/loop.wav measures a
  # healthy -6.2 dB side/mid, and the render turned that into +1.7.
  #
  # stereotools slev scales the side channel without delaying either one. It
  # widens; it cannot comb. The cost is honest and small: a mono fold loses the
  # boosted side rather than combing the mids, which is the trade every mastering
  # widener makes.
  #
  # SIDE_CEILING keeps the result under unity — a master bus that can put more
  # energy in the difference signal than the sum is not wide, it is broken.
  slev = [1.0 + 0.5 * amt, 1.45].min.round(2)
  out = "#{path}.wide#{File.extname(path)}"
  chain = "[0:a]asplit=2[mw_lo][mw_hi];" \
          "[mw_lo]lowpass=f=#{MASTER_WIDTH_HZ}[mw_low];" \
          "[mw_hi]highpass=f=#{MASTER_WIDTH_HZ}," \
          "stereotools=mlev=1:slev=#{slev}[mw_wide];" \
          "[mw_low][mw_wide]amix=inputs=2:weights=1 1:duration=first:normalize=0," \
          "alimiter=limit=0.97[mwout]"
  begin
    sh! "ffmpeg", "-y", "-v", "error", "-i", path, "-filter_complex", chain,
        "-map", "[mwout]", "-ar", SAMPLE_RATE.to_s, *codec_for(out), out
    FileUtils.mv(out, path)
    dmesg("master width: #{amt} above #{MASTER_WIDTH_HZ} Hz", unit: "mix0", parent: "dilla0")
  rescue StandardError => e
    warn "master width skipped: #{e.message}"
    FileUtils.rm_f(out)
  end
  path
end

# Wet-dominant parallel layering of the finished track against itself.
#
# Summing a processed copy with an unprocessed one is comb filtering, and how
# audible that is depends entirely on the level difference -- which is why the
# wet-strong/dry-weak direction is the safe one and a 50/50 blend is not. A dry
# layer 14 dB down puts comb notches at +-1.6 dB, below the point where it reads
# as filtering, while still returning the original attack transient underneath a
# wet path that has smeared it. At 0 dB the same sum notches +-6 dB and hollows
# out the midrange.
#
# MASTER_LAYER is the wet/dry balance, 0 (off, and the default) to 1.
# MASTER_LAYER_DRY_DB moves the dry layer; the default is the -14 dB above.
MASTER_LAYER_DRY_DB = -14.0

def master_layer_amount = ENV.fetch("MASTER_LAYER", "0").to_f.clamp(0.0, 1.0)

# A fraction of a Hz of frequency shift on the wet layer only.
#
# Frequency shifting is not pitch shifting: afreqshift displaces every partial
# by a constant number of Hz, so harmonic ratios do not survive it. That is
# ruinous at musical depths and is exactly why the value here is tiny. At 0.1 Hz
# no partial moves audibly, but the wet layer's phase rotates continuously
# against the dry with a 1/shift second beat period -- 10 seconds at the default
# -- so the two layers drift in and out of alignment forever without repeating
# and without an LFO. Above ~2 Hz it stops being drift and becomes ring
# modulation, which is where the clamp is.
def master_drift_hz = ENV.fetch("MASTER_DRIFT_HZ", "0").to_f.clamp(0.0, 2.0)

def layer_master!(path)
  amt = master_layer_amount
  return path unless amt.positive? && File.file?(path)

  dry_db = ENV.fetch("MASTER_LAYER_DRY_DB", MASTER_LAYER_DRY_DB.to_s).to_f.clamp(-40.0, 0.0)
  drift = master_drift_hz
  # asoftclip is not gain-compensated -- oversample=4 measures 4.2 dB down on
  # this bus -- so the wet path would arrive quieter than the balance asks for
  # and the dry would dominate a mix that is meant to be wet-led.
  wet = +""
  wet << "afreqshift=shift=#{drift}:level=1," if drift.positive?
  wet << "aecho=0.9:0.75:37|53|71:0.28|0.20|0.14," \
         "asoftclip=type=tanh:oversample=4,volume=4.2dB,treble=g=1.2:f=5500"
  out = "#{path}.layer#{File.extname(path)}"
  chain = "[0:a]asplit=2[ml_dry][ml_wet];" \
          "[ml_wet]#{wet}[ml_w];" \
          "[ml_dry]volume=#{(dry_db + (1.0 - amt) * -dry_db).round(2)}dB[ml_d];" \
          "[ml_w][ml_d]amix=inputs=2:weights=#{amt.round(3)} 1:duration=first:normalize=0," \
          "alimiter=limit=0.97[mlout]"
  begin
    sh! "ffmpeg", "-y", "-v", "error", "-i", path, "-filter_complex", chain,
        "-map", "[mlout]", "-ar", SAMPLE_RATE.to_s, *codec_for(out), out
    FileUtils.mv(out, path)
    dmesg("master layer: wet #{amt}, dry #{dry_db} dB#{drift.positive? ? ", drift #{drift} Hz" : ''}",
          unit: "mix0", parent: "dilla0")
  rescue StandardError => e
    warn "master layer skipped: #{e.message}"
    FileUtils.rm_f(out)
  end
  path
end

# Tape varispeed on the finished master: pitch and tempo together, by resampling.
#
# This is deliberately not a pitch shifter. Holding tempo while moving pitch
# needs a phase vocoder, which smears exactly the transients a drum record is
# made of. Resampling has no artefact to trade away at all -- it is the file
# read at a different rate, which is what a tape machine running slow does, and
# the high end comes down with everything else. That descending top end is most
# of what the effect actually sounds like.
#
# MASTER_VARISPEED is in semitones, negative for slower and lower. -1 is a 5.6%
# move and lands 92 BPM at 86.8; a lot of records that read as subtly slow are
# nearer 1-3%, so -0.2 to -0.5 is the subtle end of this knob.
#
# It runs after normalise_master!, so the loudness target is measured on the
# unshifted file. Resampling does not change level, but it does change duration:
# a track slowed a semitone is 5.9% longer than the bar count implies.
def master_varispeed_semitones = ENV.fetch("MASTER_VARISPEED", "0").to_f.clamp(-4.0, 4.0)

def varispeed_master!(path)
  semis = master_varispeed_semitones
  return path if semis.zero? || !File.file?(path)

  ratio = 2.0**(semis / 12.0)
  out = "#{path}.vari#{File.extname(path)}"
  begin
    sh! "ffmpeg", "-y", "-v", "error", "-i", path,
        "-af", "asetrate=#{(SAMPLE_RATE * ratio).round},aresample=#{SAMPLE_RATE}",
        "-ar", SAMPLE_RATE.to_s, *codec_for(out), out
    FileUtils.mv(out, path)
    dmesg("master varispeed: #{semis} st (x#{ratio.round(5)})", unit: "mix0", parent: "dilla0")
  rescue StandardError => e
    warn "master varispeed skipped: #{e.message}"
    FileUtils.rm_f(out)
  end
  path
end

# The album's sonic signature: one treatment every beat carries.
#
# A record is recognisable as a record because its tracks were finished the same
# way. Everything upstream of here varies on purpose -- progression, kit, patch,
# tape preset -- so this is the one stage that must not, and it is deliberately
# a single named identity rather than a knob per render.
#
# Four stages, each aimed at a different cause of "harsh", because they are
# different problems and one filter cannot fix them all:
#
#   DE-HARSH. Resonances between 1.8 and 5.2 kHz are what the ear calls harsh,
#   and they are intermittent -- a static EQ cut there dulls the whole track to
#   fix moments. So the band is split out and compressed on its own, hard and
#   fast, and left alone when it is not ringing. Everything outside the band is
#   untouched and re-summed.
#
#   EVEN HARMONICS. Symmetric clipping -- which every tanh stage in this engine
#   is, and there are fifty of them -- generates ODD harmonics, and odd harmonics
#   are what "overdrive" sounds like. A DC offset before the nonlinearity makes
#   it asymmetric, which generates EVEN harmonics instead: the same saturation
#   density read as warmth rather than distortion. The offset is removed after.
#
#   OVERSAMPLING. A nonlinearity at 44.1 kHz folds everything it generates above
#   Nyquist back down as inharmonic aliases, and inharmonic content is the most
#   fatiguing thing a mix can contain. asoftclip's own oversample does the whole
#   job here; it is the cheapest real win available and costs nothing but CPU.
#
#   GLUE. Slow attack, low ratio, wide knee. Not level control -- it lets
#   transients through untouched and only moves the sustain, which is what makes
#   separate parts read as one performance rather than a stack.
#
# asoftclip is not gain-compensated (4.2 dB down on this bus, measured), so the
# makeup below is a measured constant and not a guess.
MELT_MAKEUP_DB = 4.2

def melt_amount = ENV.fetch("MELT", "0").to_f.clamp(0.0, 1.0)

def melt_master!(path)
  amt = melt_amount
  return path unless amt.positive? && File.file?(path)

  drive = (0.03 + 0.05 * amt).round(4)          # DC offset -> asymmetry -> even harmonics
  ratio = (2.0 + 2.0 * amt).round(2)            # de-harsh band only
  thr   = (-22.0 - 6.0 * amt).round(1)
  out = "#{path}.melt#{File.extname(path)}"
  chain = "[0:a]asplit=3[mlow][mmid][mhigh];" \
          "[mlow]lowpass=f=1800[ml];" \
          "[mmid]highpass=f=1800,lowpass=f=5200," \
          "acompressor=threshold=#{thr}dB:ratio=#{ratio}:attack=3:release=80:knee=6[mm];" \
          "[mhigh]highpass=f=5200[mh];" \
          "[ml][mm][mh]amix=inputs=3:duration=first:normalize=0," \
          "dcshift=#{drive},asoftclip=type=tanh:oversample=8,dcshift=-#{drive},highpass=f=20," \
          "volume=#{MELT_MAKEUP_DB}dB," \
          "acompressor=threshold=-20dB:ratio=1.5:attack=150:release=450:knee=8," \
          "equalizer=f=8000:t=h:w=4000:g=#{(-0.8 * amt).round(2)}," \
          "alimiter=limit=0.97[mout]"
  begin
    sh! "ffmpeg", "-y", "-v", "error", "-i", path, "-filter_complex", chain,
        "-map", "[mout]", "-ar", SAMPLE_RATE.to_s, *codec_for(out), out
    FileUtils.mv(out, path)
    dmesg("melt: de-harsh #{ratio}:1 @1.8-5.2k, even-harmonic drive #{drive}, 8x oversampled",
          unit: "mix0", parent: "dilla0")
  rescue StandardError => e
    warn "melt skipped: #{e.message}"
    FileUtils.rm_f(out)
  end
  path
end

def normalise_master!(path, cfg)
  return path if ENV["MASTER_NORMALISE"] == "0" || !File.file?(path)

  widen_master!(path)

  # MASTER_LUFS outranks the style table. The per-style targets are a texture
  # decision made by ear and stay that way, but they are set for the Dilla-
  # leaning material this engine started as -- techno rendered through a dilla
  # family lands near -19, which is roughly 5 dB under where the genre sits and
  # 9 under a club master. It does not sound thin, it sounds small next to
  # anything else, and there was no way to say so per render short of editing
  # the table and moving every other track with it.
  env_lufs = ENV["MASTER_LUFS"].to_s.strip
  target = if env_lufs.empty?
             (cfg[:master_lufs] || MASTER_TARGET_LUFS).to_f
           else
             env_lufs.to_f
           end
  out, err, status = capture("ffmpeg", "-nostdin", "-hide_banner", "-i", path,
                             "-af", "loudnorm=I=#{target}:TP=#{TRUE_PEAK_CEILING_DB}:print_format=json",
                             "-f", "null", "-")
  unless status.success?
    warn "master normalise: measurement failed, leaving level as rendered"
    return path
  end

  json = (out + err)[/\{\s*"input_i".*?\}/m]
  measured = json ? (JSON.parse(json)["input_i"].to_f rescue nil) : nil
  if measured.nil? || measured <= -70.0
    warn "master normalise: no usable reading#{measured ? " (#{measured} LUFS)" : ''} — leaving level as rendered"
    return path
  end

  # Bounded, so a mis-measurement cannot swing a track 30 dB. Anything needing
  # more than twelve is wrong somewhere earlier and should be found there.
  gain = (target - measured).clamp(-12.0, 12.0)
  tmp = "#{path}.norm#{File.extname(path)}"
  ok = system("ffmpeg", "-nostdin", "-y", "-v", "error", "-i", path,
              "-af", "volume=#{gain.round(2)}dB," \
                     "alimiter=limit=#{TRUE_PEAK_CEILING_LINEAR}:attack=1:release=40:level=disabled",
              # codec_for, not a hardcoded 192k. Every renderer writes mp3 at 320k
              # and this pass re-encoded the finished file at 192k on the way to
              # setting its level -- a silent quality drop on every mp3 render,
              # applied by the one stage whose job was supposed to be a gain.
              *codec_for(path),
              tmp, out: File::NULL, err: File::NULL)
  if ok && File.file?(tmp) && File.size(tmp).positive?
    FileUtils.mv(tmp, path)
    dmesg("master: #{measured.round(1)} LUFS -> #{target} (#{format('%+.1f', gain)} dB, one static gain)",
          unit: "mix0", parent: "dilla0")
  else
    FileUtils.rm_f(tmp)
    warn "master normalise: re-encode failed, leaving level as rendered"
  end
  path
end

# The genre renderers' way in to the master bus.
#
# render_dilla measures its finished file and applies one gain (normalise_master!
# at the tail of its finaliser, the only call site there has ever been).
# render_hate_techno, render_industrial and render_analog each hand-rolled a
# master -- a console chain and a limiter -- and then stopped. A limiter caps a
# peak; it does not set a loudness. So those three had no integrated-loudness
# target at all, and it showed the moment they shared a playlist with a Dilla
# render: measured across a 26-track demo, the 8 parts that hashed into a techno
# slot came out at -12.3 LUFS against -18.7 for the other 18. A 6.5 dB step
# between adjacent tracks, from a stage that was never wired rather than a level
# anyone chose.
#
# This is the same fork the harmony work closed one layer up. Giving those
# renderers the progression fixed what notes they played; it did not give them
# the master, because the master lives in a finaliser only render_dilla runs.
#
# Takes a family symbol rather than a cfg: the genre renderers do not build the
# render_config hash that carries :master_lufs, and inventing a partial one to
# satisfy this call would be a worse lie than looking the number up here.
def normalise_genre_master!(destination, family)
  target = MASTER_LUFS_BY_STYLE.fetch(family, MASTER_LUFS_BY_STYLE[:default])
  normalise_master!(destination, { master_lufs: target })
end

# The AKMD / Radio Bergen chain, reproduced stage for stage. It came from
# STUDIO/radio-bergen/akmd_mastering_chain.rb, which was a description of this
# chain and nothing else — no caller, no runtime role — so it went with the rest
# of that directory rather than being carried along as a duplicate of a comment. It is a broadcast chain: band-limited, forward in
# the low mids, soft-clipped rather than brick-walled. Offered as an alternative
# to master_bus_filters_enhanced because that one stacks parallel compression, a
# sub-150Hz sidechain duck keyed off the harm bus, per-bus RMS matching,
# convolution reverb and loudnorm -- the comment on the mix assembly already
# records that the elaborate chain, not the balance numbers, was what failed
# listening tests. Nine stages, no dynamics keyed off anything else.
# MASTER_CHAIN=akmd selects it.
# Saturation rather than overdrive. The stages are the same nine; what changed
# is how hard the clipper is driven and whether its harmonics alias.
#
# It used to run makeup=4 into a bare `asoftclip=type=tanh` and then volume=1.5
# on top — about +7.5 dB pushed into a clipper with threshold at its default of
# 1, so it only engaged at full scale and engaged hard. That is an overdrive
# pedal, not a mastering chain.
#
# oversample is the change that matters most. It defaults to 1, meaning none:
# clipping generates harmonics above Nyquist and, with nowhere to go, they fold
# back down as inharmonic aliasing. That folded content is what makes digital
# clipping sound fizzy and brittle where analog sounds warm — real saturation
# has no Nyquist to fold against, its harmonics extend and roll off. At
# 4x the harmonics are generated with headroom and filtered before decimation,
# so what survives is harmonically related to the signal.
#
# The rest is gain staging: less level into the clipper, threshold lowered so it
# engages gradually across the range instead of slamming at the ceiling, and the
# level made back up after the non-linearity rather than before it. atan over
# tanh for a wider knee — it compresses the approach to clipping over more of
# the range, which reads as compression rather than distortion.
AKMD_MASTER_FILTERS = [
  # Tape rolls off; it does not cut. A highpass at 60 was taking body out of the
  # low end that the head bump then tried to put back, so both moved: 30 Hz, and
  # the bump halved to 1.5 dB. The top is a shelf now rather than a brickwall —
  # a lowpass at 11.5k sounds like a filter, a shelf sounds like tape.
  "highpass=f=30",
  "equalizer=f=55:t=q:w=1.1:g=1.5",
  "equalizer=f=9000:t=h:w=5000:g=-2.5",
  "lowpass=f=13500",
  # Tape compression is slow and shallow. 3:1 at a 10 ms attack was catching
  # every transient and flattening the record; 1.8:1 at 30 ms with a soft knee
  # lets hits through and only leans on sustained level. Measured on a raw stem
  # this is what moves total harmonic distortion from 0.166% to 0.057%.
  "acompressor=threshold=-18dB:ratio=1.8:attack=30:release=320:makeup=1.5:knee=6",
  # A symmetric curve cannot produce even harmonics. tanh and atan are both
  # odd-symmetric — f(-x) = -f(x) — so only odd orders exist. Measured on a
  # 220 Hz sine: 2nd harmonic at -131 dB, which is the numerical noise floor,
  # against a 3rd at -81. Odd orders dominating by 51 dB is the transistor edge;
  # the tube warmth people reach for is the 2nd.
  #
  # Crane Song's HEDD exposes exactly this split as triode vs pentode. The route
  # to it is asymmetry — historically a DC bias into the non-linearity, so the
  # curve treats the two halves of the wave differently.
  #
  # Bias dropped from 0.15 to 0.06 and the clipper backed off with it. The point
  # of the asymmetry was never maximum even-order content, it was which orders
  # dominate — and 0.06 still puts even on top. Threshold 0.92 with unity output
  # means the stage only touches peaks instead of rounding the whole waveform,
  # which is what it was doing at 0.72 into 1.28.
  #
  # The highpass after is not optional: biasing leaves DC on the output and
  # asymmetric clipping leaves more. Measured offset after it is 0.000002.
  "dcshift=shift=0.06",
  "asoftclip=type=atan:threshold=0.92:output=1.0:oversample=4",
  "highpass=f=22",
  # This chain used to end with +6.4 dB into a limiter set 0.7 dB from full
  # scale, on top of 9 dB already staged ahead of it. That is what "overdrive"
  # was. The limiter is a safety net here, not a loudness tool: high ceiling,
  # slow release, and it should mostly not engage at all.
  "volume=1.5",
  "alimiter=limit=0.95:attack=8:release=220",
].freeze

def akmd_master_chain?
  ENV["MASTER_CHAIN"].to_s.downcase == "akmd"
end

def akmd_master_filters(input_tag, out_tag: "out")
  ["[#{input_tag}]#{AKMD_MASTER_FILTERS.join(',')},aresample=#{SAMPLE_RATE}[#{out_tag}]"]
end

def master_bus_filters_enhanced(input_tag, cfg:, duration: nil, ir_input_idx: nil)
  return akmd_master_filters(input_tag) if akmd_master_chain?

  unless sonitex_enabled?
    filt = ["[#{input_tag}]acompressor=threshold=-20dB:ratio=2:attack=25:release=120:makeup=1.5[premaster0]"]
    filt << mix_bass_chord_balance_filter("premaster0", out_tag: "premaster")
    filt << sub_bass_mono_filter("premaster", out_tag: "monobassed")
    filt << analog_drift_filter("monobassed", out_tag: "drifted")
    darken = cfg.fetch(:mood_darken_strength, 1.0)
    filt << mood_darken_filter("drifted", out_tag: "darkened", strength: darken)
    reverb_out = "darkened"
    if ir_input_idx
      filt << convolution_reverb_filter("darkened", ir_input_idx, mix: cfg[:style_family] == :wonky ? 0.22 : 0.16, out_tag: "reverbed")
      reverb_out = "reverbed"
    end
    if analog_smooth_enabled?
      filt << analog_smooth_filter(reverb_out, out_tag: "smoothed")
      reverb_out = "smoothed"
    end
  if duration && !(camel_mode? && ENV.fetch("CAMEL_NO_BREAK", "1") != "0")
    filt << break_filter(reverb_out, duration, out_tag: "broke")
    filt << build_up_filter_enhanced("broke", duration, out_tag: "built")
    filt << true_peak_guard_for_style("built", cfg)
  else
    filt << true_peak_guard_for_style(reverb_out, cfg)
  end
  return filt
  end
  s = sonitex_config(track: cfg[:track].to_s)
  variant = analog_resolve_variant(track: cfg[:track].to_s)
  filt = []
  filt.concat(sonitex_tape_filters(input_tag, out_tag: "snx_out"))
  filt.concat(analog_emulation_filters("snx_out", variant, out_tag: "ana_out"))
  filt << "[ana_out]alimiter=limit=#{s[:limit]}:level_out=#{s[:level_out]}[premaster0]"
  filt << mix_bass_chord_balance_filter("premaster0", out_tag: "premaster")
  filt << sub_bass_mono_filter("premaster", out_tag: "monobassed")
  # Camel: skip wow drift + heavy darken — they smear the kit and delete HF.
  if camel_mode? && ENV.fetch("CAMEL_CLEAN_MASTER", "1") != "0"
    reverb_out = "monobassed"
  else
    filt << analog_drift_filter("monobassed", out_tag: "drifted")
    darken = cfg.fetch(:mood_darken_strength, 1.0)
    filt << mood_darken_filter("drifted", out_tag: "darkened", strength: darken)
    reverb_out = "darkened"
  end
  if ir_input_idx && !(camel_mode? && ENV.fetch("CAMEL_NO_REVERB", "1") != "0")
    filt << convolution_reverb_filter(reverb_out, ir_input_idx, mix: 0.12, out_tag: "reverbed")
    reverb_out = "reverbed"
  end
  if analog_smooth_enabled?
    # After the tape and analog-emulation stages, not instead of them: those
    # colour the mix, this one takes the edges off whatever they produced.
    filt << analog_smooth_filter(reverb_out, out_tag: "smoothed")
    reverb_out = "smoothed"
  end
  # break_filter bitcrushes + silences mid-track — kills pads/leads. Off on Camel.
  if duration && !(camel_mode? && ENV.fetch("CAMEL_NO_BREAK", "1") != "0")
    filt << break_filter(reverb_out, duration, out_tag: "broke")
    filt << build_up_filter_enhanced("broke", duration, out_tag: "built")
    filt << true_peak_guard_for_style("built", cfg)
  else
    filt << true_peak_guard_for_style(reverb_out, cfg)
  end
  filt
end
