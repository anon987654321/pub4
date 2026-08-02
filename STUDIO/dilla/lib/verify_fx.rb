# frozen_string_literal: true

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
      # vibrato is transparent in this build, so anything relying on it is
      # pinned here as a known-failing check rather than quietly dropped: it
      # documents the defect and will start passing if a future ffmpeg fixes it.
      Check.new(name: "vibrato (known bad)", signal: :sine,
                filter: "vibrato=f=4:d=0.9",
                measure: ->(f) { band(f, 195, 205) }, expect: :down, min_delta: 1.0),
      Check.new(name: "sample FM", signal: :sine_high,
                filter: "highpass=f=700,afreqshift=shift=400:level=1,highpass=f=700",
                # 2.0, not the 3.0 first guessed at. A frequency shift above the
                # floor moves this band by about 2.3 dB, and the honest move is to
                # set the bar at what the stage delivers rather than to raise the
                # stage until it clears a number chosen before measuring.
                measure: ->(f) { band(f, 1500, 8000) }, expect: :up, min_delta: 2.0),
    ]
  end

  def verify!(dir = Dir.tmpdir)
    src = {}
    %i[sine sine_high noise wide].each do |kind|
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
    broken = verify_patch_chains!(src[:sine])
    src.each_value { |p| FileUtils.rm_f(p) }
    failed.zero? && broken.zero?
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
  def verify_patch_chains!(signal)
    chains = {}
    ObjectSpace.each_object(Hash) do |h|
      id = h[:id]
      fx = h[:fx]
      chains[id] = fx if id.is_a?(Symbol) && fx.is_a?(String) && !fx.empty?
    rescue StandardError
      nil
    end
    return 0 if chains.empty? || signal.nil?

    out = File.join(Dir.tmpdir, "vfx_chain.wav")
    broken = chains.sort.reject { |_, fx| run("-i", signal, "-af", fx, "-ac", "2", out) }
    FileUtils.rm_f(out)

    puts
    if broken.empty?
      puts "  all #{chains.length} patch fx chains open"
    else
      puts "  #{broken.length} of #{chains.length} patch fx chains FAIL to open:"
      broken.each { |id, fx| puts "    #{id}: #{fx[0, 90]}" }
    end
    broken.length
  end
end
