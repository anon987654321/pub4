# frozen_string_literal: true

require "shellwords"

# Proves each effect stage actually does something.
#
# Every silent failure this engine has produced was the same shape: the filter
# was wired correctly, ffmpeg returned success, and the audio came out
# unchanged. asoftclip did not saturate at any threshold. `equalizer` with t=h
# is a peaking filter 0.7 Hz wide, not a shelf. A concat list with relative
# paths resolved against the wrong directory and silently returned the input.
# In each case the parameters were tuned for several rounds before anyone
# checked whether the stage was transparent to begin with.
#
# So each check states what it expects to CHANGE, and by how much. A stage that
# does not move its own measurement fails, regardless of whether it errored.
# The test signals are deliberately simple: a sine has no harmonics, so anything
# above the fundamental is the stage's own work and nothing else's.
module VerifyFx
  RATE = 44_100

  Check = Struct.new(:name, :signal, :filter, :measure, :expect, :min_delta, keyword_init: true)

  module_function

  def sine(path, freq: 200, seconds: 3)
    run("-f", "lavfi", "-i", "sine=frequency=#{freq}:duration=#{seconds}:sample_rate=#{RATE}",
        "-ac", "2", path)
    path
  end

  # Above the 700 Hz floor the FM stage works over.
  def sine_high(path) = sine(path, freq: 1200)

  def noise(path, seconds: 3)
    run("-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.5:duration=#{seconds}:r=#{RATE}",
        "-ac", "2", path)
    path
  end

  # Two uncorrelated channels, for anything that claims to act on stereo width.
  def wide(path, seconds: 3)
    run("-filter_complex",
        "anoisesrc=color=pink:amplitude=0.5:duration=#{seconds}:r=#{RATE}[l];" \
        "anoisesrc=color=white:amplitude=0.5:duration=#{seconds}:r=#{RATE}:seed=7[r];" \
        "[l][r]join=inputs=2:channel_layout=stereo[o]",
        "-map", "[o]", path)
    path
  end

  # Hot and genuinely stereo, for the colour pass.
  #
  # Three of the first five stages this pass flagged were the signal's fault,
  # not the stage's -- the same error the vibrato note above records, made again
  # the moment the probe was reused on a wider population:
  #
  #   stereo_width is extrastereo, which scales the SIDE channel. `noise` is one
  #   mono source copied to two channels, so its side is zero and any width
  #   filter nulls perfectly while working exactly as designed.
  #
  #   stylus_mistrack only acts on samples above 0.55 (it models a needle
  #   jumping on loud passages). `noise` peaks at 0.5 and never reaches it.
  #
  #   harmonic_bloom adds 0.07*val*abs(val); against a quiet source that lands
  #   at -64.7 dB, just under the floor, while doing precisely what it says.
  #
  # Amplitude 0.9 and two uncorrelated channels removes all three excuses, so a
  # stage that still nulls here has nowhere left to hide.
  def hot_wide(path, seconds: 3)
    run("-filter_complex",
        "anoisesrc=color=pink:amplitude=0.9:duration=#{seconds}:r=#{RATE}[l];" \
        "anoisesrc=color=brown:amplitude=0.9:duration=#{seconds}:r=#{RATE}:seed=11[r];" \
        "[l][r]join=inputs=2:channel_layout=stereo[o]",
        "-map", "[o]", path)
    path
  end

  def run(*args)
    system("ffmpeg", "-v", "error", "-y", *args.map(&:to_s), out: File::NULL, err: File::NULL)
  end

  def measure(path, af)
    out = `ffmpeg -v info -i "#{path}" -af "#{af}" -f null - 2>&1`
    out[/mean_volume: ([-0-9.]+)/, 1].to_f
  end

  # Energy above the fundamental. On a pure sine this can only be harmonics the
  # stage invented, which is the one unambiguous test for saturation.
  def harmonics(path) = measure(path, "highpass=f=500,volumedetect")

  # Difference signal. Falls when a stage sums toward mono, rises when it widens.
  def side(path, hz = 200)
    measure(path, "lowpass=f=#{hz},pan=mono|c0=0.5*c0-0.5*c1,volumedetect")
  end

  def band(path, lo, hi) = measure(path, "highpass=f=#{lo},lowpass=f=#{hi},volumedetect")

  def checks
    [
      Check.new(name: "bus saturation", signal: :sine,
                filter: "volume=6,alimiter=limit=0.2:level_out=1,volume=0.25",
                measure: ->(f) { harmonics(f) }, expect: :up, min_delta: 6.0),
      Check.new(name: "cymbal dirt", signal: :noise,
                filter: "aphaser=in_gain=0.6:delay=3:decay=0.3:speed=0.5," \
                        "flanger=delay=5:depth=2:regen=10",
                measure: ->(f) { band(f, 6000, 14_000) }, expect: :any, min_delta: 0.5),
      Check.new(name: "master tilt", signal: :noise,
                filter: "bass=f=175:g=1.5:width_type=q:w=0.7," \
                        "treble=f=4200:g=-1.5:width_type=q:w=0.7",
                measure: ->(f) { band(f, 40, 400) - band(f, 5000, 14_000) },
                expect: :up, min_delta: 1.0),
      Check.new(name: "mono bass", signal: :wide,
                filter: "asplit=2[a][b];[a]lowpass=f=200," \
                        "pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1[m];" \
                        "[b]highpass=f=200[s];[m][s]amix=inputs=2:normalize=0",
                measure: ->(f) { side(f) }, expect: :down, min_delta: 3.0),
      Check.new(name: "loop delay", signal: :sine,
                filter: "aecho=0.8:0.32:489:0.28",
                measure: ->(f) { measure(f, "volumedetect") }, expect: :any, min_delta: 0.3),
      # vibrato works; this check did not.
      #
      # It was pinned as "known bad" on the conclusion that the filter was
      # transparent in this build. It is not: measured against a five kilohertz
      # tone, a depth of 0.9 swings the pitch by plus or minus 0.9 percent, and
      # the depth maps one-to-one onto percent. The fault was in the
      # measurement. A 200 Hz tone moved by 0.9 percent lands 1.8 Hz away, and
      # the check then asked whether it had LEFT a band ten hertz wide. It never
      # does, because it never goes near the edge.
      #
      # Nor could `band` ever have shown it. That helper is a highpass and a
      # lowpass in series, and their skirts are far too gentle to care whether a
      # tone has moved eleven hertz -- a second attempt narrowing it to four
      # hertz wide also read exactly 0.0 dB. A resonant bandpass is the probe
      # that resolves it: dry -24.3 dB, with vibrato -38.2 dB, a fall of nearly
      # fourteen.
      #
      # The lesson is the one this file exists to enforce, turned on the file
      # itself. A failing check is a claim about the world, and it has to be
      # verified like any other before it is written down as somebody else's
      # defect. This one accused ffmpeg for as long as it stood.
      Check.new(name: "vibrato", signal: :sine_high,
                filter: "vibrato=f=4:d=0.9",
                measure: ->(f) { measure(f, "bandpass=f=1200:width_type=h:width=4,volumedetect") },
                expect: :down, min_delta: 6.0),
      Check.new(name: "sample FM", signal: :sine_high,
                filter: "highpass=f=700,afreqshift=shift=400:level=1,highpass=f=700",
                # 2.0, not the 3.0 first guessed at. A frequency shift above the
                # floor moves this band by about 2.3 dB, and the honest move is to
                # set the bar at what the stage delivers rather than to raise the
                # stage until it clears a number chosen before measuring.
                measure: ->(f) { band(f, 1500, 8000) }, expect: :up, min_delta: 2.0),
    ]
  end

  # --- the null test ---------------------------------------------------------
  #
  # Each check above states what one stage should do to one property, and that
  # is the strongest claim a test here can make. It also costs a hand-tuned
  # probe per stage -- see the vibrato note for how long one wrong probe stood
  # -- which is why seven stages had one and the thirty-three colour stages the
  # engine actually renders through had none.
  #
  # A weaker claim scales to all of them: send the signal through the stage,
  # invert it against the dry signal, sum the two. If the residual is silence
  # then not one sample changed, whatever ffmpeg reported on the way out. That
  # is precisely the failure this file was written for, and it needs no
  # knowledge of what the stage was trying to do.
  #
  # Measured on this build against known cases: `anull` and `volume=1` both null
  # to -91.0 dB, the 16-bit floor; `volume=2` leaves -24.1, `highpass=f=800`
  # -23.6, `aecho` -27.5, `vibrato` -21.9. Sixty decibels between the two
  # populations, so the threshold below carries no judgement -- anything a
  # listener could ever hear clears it by a wide margin.
  NULL_FLOOR_DB = -60.0

  NULL_GRAPH = "[1:a]volume=-1[inv];[0:a][inv]amix=inputs=2:normalize=0,volumedetect[o]"

  def null_residual_db(dry, wet)
    cmd = "ffmpeg -v info -i #{Shellwords.escape(dry)} -i #{Shellwords.escape(wet)} " \
          "-filter_complex #{Shellwords.escape(NULL_GRAPH)} -map '[o]' -f null - 2>&1"
    `#{cmd}`[/mean_volume: (-?[0-9.]+)/, 1]&.to_f
  end

  # Runs `filter` over `signal` and reports [opened?, residual_db].
  def null_test(signal, filter, dir)
    wet = File.join(dir, "vfx_null.wav")
    opened = run("-i", signal, "-af", filter, "-ac", "2", wet)
    residual = opened && File.file?(wet) ? null_residual_db(signal, wet) : nil
    FileUtils.rm_f(wet)
    [opened, residual]
  end

  # Every named colour stage the engine can put a record through.
  #
  # grade_filter and Outboard are dilla.rb's, so this only populates when
  # verify-fx runs the way it is dispatched -- inside the engine. Required on
  # its own, verify_fx still runs the seven checks and skips this pass rather
  # than crashing.
  #
  # stc8 takes a tempo and `chain` composes other units rather than being one,
  # so they are handled and excluded respectively.
  def colour_stages
    stages = {}
    if defined?(grade_filter) && defined?(AUDIO_STOCKS)
      stock = AUDIO_STOCKS[:tape_500]
      GRADE_PRESETS_FOR_VERIFY.each do |fx|
        f = begin
          grade_filter(fx, stock)
        rescue StandardError
          nil
        end
        stages["grade:#{fx}"] = f if f.is_a?(String) && !f.empty?
      end
    end
    if defined?(Outboard)
      units = Outboard.methods(false).map(&:to_s) - %w[chain]
      units.sort.each do |u|
        f = begin
          u == "stc8" ? Outboard.stc8(bpm: 90.0) : Outboard.send(u)
        rescue StandardError, ArgumentError
          nil
        end
        stages["outboard:#{u}"] = f if f.is_a?(String) && !f.empty?
      end
    end
    stages
  end

  # The 20 arms of grade_filter's case. Listed rather than parsed out of the
  # source: a stage that gets renamed should break this loudly here, not vanish
  # from the verification quietly.
  GRADE_PRESETS_FOR_VERIFY = %w[
    tape_saturation analog_noise harmonic_bloom spectral_warmth parallel_compress
    multiband_tone wow_flutter vinyl_crackle transient_sharpen stereo_width
    print_through_echo reel_splice_clicks stylus_mistrack platter_wow
    needle_drop_fade haas_jitter spring_reverb plate_reverb chamber_reverb dub_delay
  ].freeze

  def verify_colour_stages!(signal, dir)
    stages = colour_stages
    if stages.empty?
      puts
      puts "  colour stages: skipped (run as `ruby dilla.rb verify-fx`, not standalone)"
      return 0
    end

    dead = []
    stages.sort.each do |name, filter|
      opened, residual = null_test(signal, filter, dir)
      if !opened
        dead << [name, "FAILS TO OPEN"]
      elsif residual.nil?
        dead << [name, "no output"]
      elsif residual <= NULL_FLOOR_DB
        dead << [name, format("transparent (%.1f dB residual)", residual)]
      end
    end

    puts
    if dead.empty?
      puts "  all #{stages.length} colour stages change the audio"
    else
      puts "  #{dead.length} of #{stages.length} colour stages do NOTHING:"
      dead.each { |name, why| puts "    #{name}: #{why}" }
    end
    dead.length
  end

  def verify!(dir = Dir.tmpdir)
    src = {}
    %i[sine sine_high noise wide hot_wide].each do |kind|
      p = File.join(dir, "vfx_#{kind}.wav")
      send(kind, p)
      src[kind] = p
    end

    rows = checks.map do |c|
      before = c.measure.call(src[c.signal])
      out = File.join(dir, "vfx_out.wav")
      ok_run = run("-i", src[c.signal], "-filter_complex", c.filter, "-ac", "2", out)
      after = ok_run && File.file?(out) ? c.measure.call(out) : nil
      FileUtils.rm_f(out)
      delta = after ? (after - before) : nil
      pass =
        if delta.nil? then false
        elsif c.expect == :up then delta >= c.min_delta
        elsif c.expect == :down then delta <= -c.min_delta
        else delta.abs >= c.min_delta
        end
      [c.name, before, after, delta, pass, c.expect, c.min_delta]
    end

    puts format("  %-16s %8s %8s %8s  %-8s %s", "stage", "before", "after", "delta", "expect", "")
    rows.each do |name, before, after, delta, pass, expect, min_delta|
      puts format("  %-16s %8.1f %8s %8s  %-8s %s",
                  name, before, after ? format("%.1f", after) : "n/a",
                  delta ? format("%+.1f", delta) : "n/a",
                  "#{expect} #{min_delta}", pass ? "ok" : "FAILED — stage is transparent")
    end
    failed = rows.count { |r| !r[4] }
    puts
    puts failed.zero? ? "  all #{rows.size} stages verified" : "  #{failed} of #{rows.size} FAILED"

    # Before the cleanup, not after: the chain check needs the sine that the
    # line below deletes. Run after it, every chain fails for want of an input
    # and the check reports 178 broken patches instead of the one real one --
    # which is what it did on its first run.
    broken = verify_patch_chains!(src[:hot_wide], dir)
    dead = verify_colour_stages!(src[:hot_wide], dir)
    src.each_value { |p| FileUtils.rm_f(p) }
    failed.zero? && broken.zero? && dead.zero?
  end

  # Does every registered patch effect chain even OPEN?
  #
  # The checks above ask whether a stage is transparent. This asks something
  # cruder and, as it turned out, more urgent: whether ffmpeg will accept the
  # string at all. A chain that fails to open takes every stage in it down --
  # the render catches the error, logs "patch fx skipped", and hands you the
  # patch completely dry.
  #
  # glass_fm_pad carried aphaser=speed=0.08 against a valid range of [0.1, 2.0].
  # It had presumably always been wrong, and nobody could have known: the voice
  # is reachable only through stack_glass, which was one of 24 pad voices that
  # no rotation table referenced. The moment DEMO_PAD_ROTATION was widened to
  # include it, it failed twice in one eight-track render.
  #
  # One out of 178 chains was broken. The other 177 are the reason this is worth
  # keeping -- it is cheap, and the failure it catches is invisible in the audio
  # unless you already know which patch to listen for.
  # Opening is necessary, not sufficient. A chain that opens and leaves the
  # audio untouched hands you the same dry patch as one that failed, and only
  # the second announces itself -- so both are counted here now.
  def verify_patch_chains!(signal, dir = Dir.tmpdir)
    chains = {}
    ObjectSpace.each_object(Hash) do |h|
      id = h[:id]
      fx = h[:fx]
      chains[id] = fx if id.is_a?(Symbol) && fx.is_a?(String) && !fx.empty?
    rescue StandardError
      nil
    end
    return 0 if chains.empty? || signal.nil?

    closed = []
    inert = []
    chains.sort.each do |id, fx|
      opened, residual = null_test(signal, fx, dir)
      if !opened
        closed << [id, fx]
      elsif residual && residual <= NULL_FLOOR_DB
        inert << [id, residual]
      end
    end

    puts
    if closed.empty? && inert.empty?
      puts "  all #{chains.length} patch fx chains open and change the audio"
    else
      unless closed.empty?
        puts "  #{closed.length} of #{chains.length} patch fx chains FAIL to open:"
        closed.each { |id, fx| puts "    #{id}: #{fx[0, 90]}" }
      end
      unless inert.empty?
        puts "  #{inert.length} of #{chains.length} patch fx chains open and do NOTHING:"
        inert.each { |id, r| puts format("    %s: %.1f dB residual", id, r) }
      end
    end
    closed.length + inert.length
  end
end
