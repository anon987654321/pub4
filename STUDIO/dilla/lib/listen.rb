# frozen_string_literal: true

# Measurement: the master heuristics, taste, the ffmpeg probe, the mix score,
# effect verification and the spectral audit, which runs on its own as `ruby
# lib/listen.rb [out_dir]`.

require "yaml"
require "open3"

# Mastering/mix heuristics — harshness, club IR, phone preview, cassette, balance.
# The persona critique is MASTER's /critique (Review::Council::Critique), so
# nothing here reimplements it.
module DillaMaster
  IR_DIR = File.join(File.expand_path("..", __dir__), "samples", "irs")
  REFERENCE_PATH = File.expand_path("../data/dilla_reference.yml", __dir__)

  module_function

  def enabled?
    ENV["MASTER_HEURISTICS"] == "1"
  end

  def loss_gates
    return {} unless File.file?(REFERENCE_PATH)

    YAML.safe_load_file(REFERENCE_PATH)["loss_gates"] || {}
  # Psych::Exception descends from RuntimeError, so StandardError already
  # covers a malformed reference file; naming both said the opposite.
  rescue StandardError
    {}
  end

  # Hard pre-flight reject, not an advisory score — a take failing this
  # should not be promoted regardless of beauty/groove. Only checks metrics
  # actually present in `report` (crest_factor_db from analyze_audio's
  # `dynamics` block is real; kick/bass timing correlation and the 200-400Hz
  # mud-zone level aren't measured anywhere in this engine yet, so those two
  # gates are honest no-ops — `skipped`, not silently passed — until that
  # analysis exists).
  def passes_loss_gates?(report, path: nil)
    gates = loss_gates
    return { pass: true, failures: [], skipped: [] } if gates.empty? || !report

    failures = []
    skipped = []

    crest = report.dig(:dynamics, :crest_factor_db) || report.dig("dynamics", "crest_factor_db")
    if crest
      min = gates["crest_factor_min_db"]
      failures << "crest_factor #{crest.round(1)}dB < #{min}dB (over-compressed)" if min && crest < min
    else
      skipped << "crest_factor (not present in report)"
    end

    corr = report[:kick_bass_correlation] || report["kick_bass_correlation"]
    if corr
      max = gates["kick_bass_correlation_max"]
      failures << "kick_bass_correlation #{corr.round(2)} > #{max} (reads quantized)" if max && corr > max
    else
      skipped << "kick_bass_correlation (not measured by this engine yet)"
    end

    mud = report[:mud_db_200_400hz] || report["mud_db_200_400hz"]
    mud ||= mud_db_200_400hz(path) if path && File.file?(path)
    if mud
      max = gates["mud_max_db_200_400hz"]
      failures << "mud #{mud.round(1)}dB > #{max}dB (200-400Hz masking snare body)" if max && mud > max
    else
      skipped << "mud_db_200_400hz (no audio path or report value given)"
    end

    phase = report[:stereo_phase_correlation] || report["stereo_phase_correlation"]
    phase ||= (path && File.file?(path) ? min_phase_correlation(path) : nil)
    if phase
      min = gates["stereo_phase_correlation_min"]
      failures << "stereo_phase_correlation #{phase.round(2)} < #{min} (mono cancellation risk)" if min && phase < min
    else
      skipped << "stereo_phase_correlation (no audio path given)"
    end

    # LUFS / true-peak are already measured by `dilla_quality`. Promotion used
    # to ignore them, so a take that `quality` itself warned about could still
    # land in promoted_profiles.json. The numbers live in this file's yaml so
    # the range is one source, not a second copy of DILLA_QUALITY_LUFS_TARGET.
    tp = report[:true_peak_dbtp] || report["true_peak_dbtp"]
    if tp
      max_tp = gates["true_peak_max_dbtp"]
      failures << "true_peak #{tp.round(1)} dBTP > #{max_tp} dBTP (intersample clip on lossy codecs)" if max_tp && tp > max_tp
    else
      skipped << "true_peak_dbtp (not present in report)"
    end

    lufs = report[:integrated_lufs] || report["integrated_lufs"]
    if lufs
      min_l = gates["integrated_lufs_min"]
      max_l = gates["integrated_lufs_max"]
      failures << "integrated_lufs #{lufs.round(1)} < #{min_l} (below the style spread)" if min_l && lufs < min_l
      failures << "integrated_lufs #{lufs.round(1)} > #{max_l} (above the style spread)" if max_l && lufs > max_l
    else
      skipped << "integrated_lufs (not present in report)"
    end

    { pass: failures.empty?, failures:, skipped: }
  end

  # Minimum L/R phase correlation across the whole file — 1.0 is mono-identical
  # (perfectly safe), 0.0 is fully decorrelated, negative cancels when summed
  # to mono. Reports the worst moment, not the average, since a single bad
  # section is what actually breaks on a mono sum.
  def min_phase_correlation(path)
    out, = ToolRun.capture2(
      "ffmpeg", "-hide_banner", "-v", "error", "-i", path, "-af",
      "aphasemeter=video=0,ametadata=print:key=lavfi.aphasemeter.phase:file=-",
      "-f", "null", "-"
    )
    values = out.scan(/lavfi\.aphasemeter\.phase=(-?[\d.]+)/).flatten.map(&:to_f)
    values.min
  rescue StandardError
    nil
  end

  # Average level in the 200-400Hz "mud zone" (center 283Hz, ~1 octave wide)
  # — sustained energy here masks snare body and reads as boxy/undefined.
  def mud_db_200_400hz(path)
    out, = ToolRun.capture2(
      "ffmpeg", "-hide_banner", "-v", "error", "-i", path, "-af",
      "bandpass=f=283:w=200,astats=metadata=1:reset=0,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-",
      "-f", "null", "-"
    )
    values = out.scan(/lavfi\.astats\.Overall\.RMS_level=(-?[\d.]+)/).flatten.map(&:to_f)
    return if values.empty?

    (values.sum / values.length).round(2)
  rescue StandardError
    nil
  end

  def club_ir_path
    return unless enabled?
    custom = ENV["CLUB_IR"]
    return custom if custom && File.file?(custom)
    File.join(IR_DIR, "club.wav") if File.file?(File.join(IR_DIR, "club.wav"))
  end

  # Build a single labeled chain: [in]filter1,filter2[out]
  # Never prefix the first filter with a comma — ffmpeg 8 treats
  # "[pad],alimiter=..." as an empty filter name and fails with exit 8
  # ("No such filter: ''"), which silently kills every stream track.
  def extra_filters(input_tag, cfg:, duration:, section_fn: nil)
    return [] unless enabled?
    parts = []
    parts.concat(perceptual_limiter_parts) if ENV["PERCEPTUAL_LIMIT"] != "0"
    parts.concat(harshness_notch_parts) if ENV["HARSHNESS_NOTCH"] != "0"
    parts.concat(cassette_wow_parts) if ENV["CASSETTE_PRINT"] == "1"
    if ENV["RADIO_CLUB_MORPH"] == "1"
      parts.concat(radio_club_morph_parts(cfg, duration, section_fn))
    end
    return [] if parts.empty?
    tag = "#{input_tag}_mh"
    ["[#{input_tag}]#{parts.join(',')}[#{tag}]"]
  end

  def perceptual_limiter_parts
    %w[alimiter=limit=0.92:level_out=0.94 equalizer=f=3500:t=o:w=1.2:g=-1.5]
  end

  def harshness_notch_parts
    %w[equalizer=f=4200:t=h:w=800:g=-2.5 equalizer=f=6800:t=h:w=1200:g=-1.8]
  end

  def cassette_wow_parts
    %w[vibrato=f=0.25:d=0.003 acrusher=bits=11:samples=2:mix=0.12]
  end

  def radio_club_morph_parts(_cfg, duration, _section_fn)
    mid = (duration.to_f * 0.5).round(2)
    [DillaAutomation.volume_filter([[0, 0.92], [mid, 1.08]])]
  end

  def radio_club_morph(cfg, duration, section_fn = nil)
    ",#{radio_club_morph_parts(cfg, duration, section_fn).join(',')}"
  end

  def phone_preview_chain
    # mono output has only c0 — c1= is invalid on ffmpeg 8.x pan=mono
    "highpass=f=180,lowpass=f=3800,pan=mono|c0=0.5*c0+0.5*c1,alimiter=limit=0.9"
  end

  # Ear-level roughness lives in 2–4 kHz. The old meter was a two-band
  # ratio split at 3.5 kHz, so that region sat inside `mid` and cancelled —
  # a render measured −24.5 (un-harsh) while sounding rough. Three-band:
  # body (180–2 kHz) vs presence (2–4 kHz) vs air (4 kHz+). Harshness is
  # presence standing above the body. Air being hotter is brightness, not
  # roughness. `needs_notch` keeps the 6 dB threshold so the quality gate
  # does not suddenly retry every take; the number it compares is now the
  # band people actually hear. Callers that still pass only mid/high fall
  # back to the old ratio rather than inventing a presence band.
  def analyze_harshness(spectrum)
    body = spectrum[:body] || spectrum["body"]
    presence = spectrum[:presence] || spectrum["presence"]
    air = spectrum[:air] || spectrum["air"]
    if body && presence
      delta = presence.to_f - body.to_f
      {
        harshness: delta.round(2),
        needs_notch: delta > 6.0,
        body_db: body.to_f.round(2),
        presence_db: presence.to_f.round(2),
        air_db: (air || spectrum[:high] || spectrum["high"] || -30.0).to_f.round(2),
      }
    else
      high = spectrum[:high] || spectrum["high"] || -30.0
      mid = spectrum[:mid] || spectrum["mid"] || -20.0
      delta = high.to_f - mid.to_f
      { harshness: delta.round(2), needs_notch: delta > 6.0 }
    end
  end

  # harmony_score kept in the signature for call-site compatibility but no
  # longer used: it used to force "boost_sub" whenever chord/voicing quality
  # was mediocre, regardless of the actual measured low/mid balance -- two
  # unrelated quality dimensions conflated into one wrong EQ recommendation.
  # refine_deep_mix_env! trusts this recommendation directly (bumps
  # KICK_GAIN on "boost_sub" with no independent delta check), so a bad
  # chord score alone could silently push the kick louder for no acoustic
  # reason. render_quality_acceptable?'s sub_ok already worked around this
  # by re-checking low_mid_delta itself -- that guard is now redundant but
  # harmless.
  def sub_kick_balance(spectrum, harmony_score = nil)
    low = spectrum[:low] || spectrum["low"] || -18.0
    mid = spectrum[:mid] || spectrum["mid"] || -22.0
    ratio = low.to_f - mid.to_f
    rec = if ratio < -8
            "boost_sub"
          else
            ratio > 2 ? "reduce_sub" : "ok"
          end
    { low_mid_delta: ratio.round(2), recommendation: rec }
  end

  def groove_vinyl_level(ghost_count, kick_count)
    base = 0.06
    return base unless enabled? && ENV["GROOVE_VINYL"] != "0"
    g = ghost_count.to_f / [kick_count, 1].max
    (base + g * 0.015).clamp(0.04, 0.14).round(3)
  end

  def apply_phone_preview!(path)
    tmp = "#{path}.phone.wav"
    ToolRun.system("ffmpeg", "-y", "-i", path, "-af", phone_preview_chain, "-c:a", "pcm_s16le", tmp)
    File.exist?(tmp) ? tmp : path
  end

  # Laptop/phone speaker listenability — mid presence, no mud, no piercing highs.
  def phone_preview_acceptable?(spectrum)
    mid = (spectrum[:mid] || spectrum["mid"] || -40.0).to_f
    low = (spectrum[:low] || spectrum["low"] || -30.0).to_f
    harsh = analyze_harshness(spectrum)
    low_mid = low - mid
    mid_ok = mid > -32.0
    mud_ok = low_mid < 4.0
    ok = mid_ok && mud_ok && !harsh[:needs_notch]
    {
      ok:, mid_db: mid.round(2), low_mid_delta: low_mid.round(2),
      harshness: harsh[:harshness], needs_notch: harsh[:needs_notch],
    }
  end
end

require "json"

# What separates the takes you keep from the ones you delete.
#
# Every other tuning surface in this engine asks somebody to name a number.
# Nobody can name the number for "beautiful", including and especially me: I
# cannot hear these renders, and the measurements I can take are only worth
# something once they are anchored to takes an ear has already sorted. So this
# does not score a beat. It takes two piles the operator has made -- kept and
# rejected -- measures both, and reports only the dimensions where the piles
# actually separate.
#
# That last part is the whole design. Twenty measurements over six files will
# always show differences; most of them are noise. A dimension is reported only
# when the two groups barely overlap, expressed as the gap between them relative
# to their spread (a t-like separation, not a p-value -- these are samples of
# five, and pretending otherwise would be the kind of confident wrong number
# this engine has been bitten by). Everything else is listed as "no separation",
# which is a real answer: it means that dimension is not what you are hearing.
#
#   dilla taste keep/*.wav -- reject/*.wav
#
# The output is a list of sentences and, where the separation is clean, the knob
# that moves that dimension. It stops there. It does not write a default,
# because a default that changes how a render sounds is the operator's, and
# because five takes is a hint, not a mandate.
module DillaTaste
  # Each dimension: how to measure it, and which knob moves it. The knob is
  # named so a finding is actionable; nothing here sets one.
  #
  # Every uppercase name here is checked against DillaKnobs by the suite. Two of
  # them were not knobs: MASTER_TARGET_LRA and MASTER_TARGET_LUFS, which the
  # engine reads nowhere. So this module's whole output -- a dimension, a
  # separation, and the knob that moves it -- ended by naming a control that does
  # not exist, on the two dimensions an operator is most likely to act on.
  #
  # That is the same defect this file exists to avoid in the other direction: a
  # confident number nobody can act on. Advice about a knob that is not there is
  # worse than no advice, because it is followed.
  #
  # LRA has no single knob and saying so is the honest answer -- it falls out of
  # the arrangement and the master compression, which is why both are named
  # rather than one invented.
  DIMENSIONS = {
    "loudness range (LRA)" => { units: "LU", knob: "SECTION_LAYERS, the master bus compression" },
    "integrated loudness" => { units: "LUFS", knob: "MASTER_LUFS (STREAM_LUFS in a stream)" },
    "true peak" => { units: "dBTP", knob: "the limiter" },
    "transient density" => { units: "onsets/s", knob: "GHOST_TIER, DRUM_CHOPS, the drum feel" },
    "low-versus-mid balance" => { units: "dB", knob: "KICK_GAIN, BASS_MIX_WEIGHT, SAMPLE_LOOP_SUB_DB" },
    "high-frequency energy" => { units: "dB", knob: "SAMPLE_EXCITE, SAMPLE_LOOP_LP" },
    "stereo width" => { units: "ratio", knob: "stereo_pan, apulsator amount" },
    "dynamic spread" => { units: "dB", knob: "the master bus compression" },
    "silence ratio" => { units: "ratio", knob: "phrase dropouts, kick sparsity, section arrangement" },
    "crest factor" => { units: "dB", knob: "transient shaping, drum dynamics, bus compression" },
  }.freeze

  class << self
    def measure(path)
      return unless File.file?(path)

      values = {}
      values.merge!(loudness(path))
      values.merge!(bands(path))
      values.merge!(rhythm(path))
      values["stereo width"] = width(path)
      values.compact
    end

    # A pile against a pile.
    def compare(kept_paths, rejected_paths)
      kept = kept_paths.filter_map { |p| measure(p) }
      rejected = rejected_paths.filter_map { |p| measure(p) }
      return { error: "need at least two files on each side" } if kept.length < 2 || rejected.length < 2

      findings = DIMENSIONS.keys.filter_map do |dimension|
        a = kept.filter_map { |m| m[dimension] }
        b = rejected.filter_map { |m| m[dimension] }
        next if a.length < 2 || b.length < 2

        { dimension:, kept: stats(a), rejected: stats(b), separation: separation(a, b),
          knob: DIMENSIONS[dimension][:knob], units: DIMENSIONS[dimension][:units] }
      end
      { kept: kept.length, rejected: rejected.length,
        findings: findings.sort_by { |f| -f[:separation] } }
    end

    # How far apart two groups are, in units of their own spread. Above about
    # 1.5 the piles barely overlap; below 0.8 there is nothing here.
    def separation(a, b)
      ma = a.sum / a.length.to_f
      mb = b.sum / b.length.to_f
      pooled = Math.sqrt((variance(a) + variance(b)) / 2.0)
      return 0.0 if pooled < 1e-9

      ((ma - mb).abs / pooled).round(2)
    end

    def variance(values)
      m = values.sum / values.length.to_f
      values.sum { |v| (v - m)**2 } / [values.length - 1, 1].max
    end

    def stats(values)
      m = values.sum / values.length.to_f
      { mean: m.round(2), spread: Math.sqrt(variance(values)).round(2),
        min: values.min.round(2), max: values.max.round(2) }
    end

    private

    def ffmpeg(path, filter)
      FfmpegProbe.run(path, filter)
    rescue FfmpegProbe::Error
      ""
    end

    # The summary, never a running frame: see FfmpegProbe.ebur128_summary.
    def loudness(path)
      reading = FfmpegProbe.ebur128_summary(ffmpeg(path, "ebur128=peak=true"))
      { "integrated loudness" => reading[:i], "loudness range (LRA)" => reading[:lra], "true peak" => reading[:tp] }
    end

    def bands(path)
      low = band_level(path, 40, 160)
      mid = band_level(path, 400, 3000)
      high = band_level(path, 6000, 16_000)
      {
        "low-versus-mid balance" => (low && mid ? (low - mid).round(2) : nil),
        "high-frequency energy" => (high && mid ? (high - mid).round(2) : nil),
      }
    end

    def band_level(path, low, high)
      out = ffmpeg(path, "highpass=f=#{low},lowpass=f=#{high},astats=measure_overall=RMS_level:measure_perchannel=none")
      out[/RMS level dB:\s*(-?[\d.]+)/, 1]&.to_f
    end

    # Onsets per second and the peak-to-RMS spread, from one decode.
    def rhythm(path)
      raw = ToolRun.capture2(["ffmpeg", "-v", "quiet", "-i", path.to_s, "-ac", "1", "-ar", "8000", "-f", "s16le", "-"], binmode: true).first
      return {} if raw.nil? || raw.empty?

      samples = raw.unpack("s<*")
      env = samples.each_slice(80).map { |c| Math.sqrt(c.sum { |v| v.to_f * v } / c.length) }
      return {} if env.length < 10

      mean = env.sum / env.length
      rms = Math.sqrt(env.sum { |value| value * value } / env.length)
      onsets = (1...env.length).count { |i| env[i] > mean * 1.6 && env[i] > env[i - 1] * 1.5 }
      peak = env.max
      silence_cut = mean * 0.18
      {
        "transient density" => (onsets / (env.length / 100.0)).round(3),
        "dynamic spread" => (peak.positive? && mean.positive? ? (20 * Math.log10(peak / mean)).round(2) : nil),
        "silence ratio" => (env.count { |value| value <= silence_cut }.to_f / env.length).round(4),
        "crest factor" => (peak.positive? && rms.positive? ? (20 * Math.log10(peak / rms)).round(2) : nil),
      }
    end

    # Side energy over mid energy. A mono file reads 0.
    def width(path)
      out = ffmpeg(path, "astats=measure_overall=RMS_level:measure_perchannel=RMS_level")
      levels = out.scan(/RMS level dB:\s*(-?[\d.]+)/).flatten.map(&:to_f)
      return nil if levels.length < 3

      # channel 1, channel 2, overall — a crude but stable width proxy.
      (levels[0] - levels[1]).abs.round(3)
    end
  end
end

require "json"
require "open3"

# One way to run ffmpeg, ffprobe or any other tool that is not a render step.
#
# sh! runs the render steps: it writes to dmesg, reads the error tail and
# raises. Everything else -- a measurement read off stderr, raw samples read
# off stdout, a quiet conversion whose failure the caller handles -- called
# Open3, IO.popen or Kernel#system directly, and none of those can time out.
# A decode that hangs on a truncated file then held a render, a demo part or
# a test forever. These keep each call's own contract (the same return
# values, the same nil for a missing binary) and add the two things every
# call needs: a deadline, and a child that cannot stop on SIGTTIN.
#
# The child runs in its own process group with no terminal on stdin, because
# a tool that polls stdin (ffmpeg's interactive q) is stopped by the terminal
# otherwise and sits until something kills it. On the deadline the whole
# group is killed, since ffmpeg forks.
module ToolRun
  module_function

  def timeout = Integer(ENV.fetch("DILLA_TOOL_TIMEOUT", "900"))

  # Open3.capture3 with a deadline: [stdout, stderr, status]. A run past the
  # deadline returns what it wrote, a failed status, and says so on stderr.
  def capture3(*argv, stdin_data: nil, binmode: false, timeout: self.timeout, **spawn)
    Open3.popen3(*argv.flatten.map(&:to_s), pgroup: true, **spawn) do |stdin, out, err, wait|
      [stdin, out, err].each(&:binmode) if binmode
      writer = stdin_data && Thread.new { feed(stdin, stdin_data) }
      stdin.close unless writer
      readers = [out, err].map { |io| Thread.new { io.read } }
      expired = !wait_or_stop(wait.pid) { wait.join(timeout) }
      kill_group(wait.pid) if expired
      writer&.join
      output, error = readers.map(&:value)
      error = "#{error}\n#{argv.flatten.first} timeout after #{timeout}s" if expired
      [output, error, wait.value]
    end
  end

  # Open3.capture2: stdout and the status, stderr passed to the terminal.
  def capture2(*argv, **options)
    output, error, status = capture3(*argv, **options)
    $stderr.write(error) unless error.to_s.empty?
    [output, status]
  end

  # Open3.capture2e: stdout and stderr in one string, and the status.
  def capture2e(*argv, **options)
    output, error, status = capture3(*argv, **options)
    ["#{output}#{error}", status]
  end

  # Kernel#system with a deadline: true, false, or nil when the binary is
  # missing, and $? set in the calling thread as system sets it.
  def system(*argv, timeout: self.timeout, **spawn)
    pid = Process.spawn(*argv.flatten.map(&:to_s), { in: File::NULL, pgroup: true }.merge(spawn))
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    wait_or_stop(pid) do
      until Process.wait2(pid, Process::WNOHANG)
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          kill_group(pid)
          Process.wait2(pid)
          return false
        end
        sleep 0.02
      end
    end
    $?.success?
  rescue Errno::ENOENT
    nil
  end

  # Writes the input and closes the pipe, which is the child's end of input. A
  # child that exits before reading all of it closes its end first.
  def feed(stdin, data)
    stdin.write(data)
  rescue Errno::EPIPE
    nil
  ensure
    stdin.close
  end

  def kill_group(pid)
    Process.kill("-KILL", pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  # How long a child has to act on a forwarded signal before it is killed.
  # ffmpeg answers SIGINT by closing the file it is writing, which takes a
  # moment; a tool that ignores the signal gets no longer than this.
  STOP_GRACE_SEC = 2.0

  # Runs the wait in the block, and takes the child down with this process if a
  # signal ends the wait.
  #
  # The child leads its own process group, so Ctrl-C at the terminal reaches
  # this process and never the tool. Ruby turns SIGINT and SIGTERM into an
  # exception in the waiting thread, the exception unwinds past the wait, and
  # the tool -- with every process it forked -- carries on under init, still
  # writing, still holding a CPU. So the signal is passed on to the group, the
  # group is given a moment and then killed, the child is reaped, and the
  # exception carries on exactly as it arrived.
  def wait_or_stop(pid, group: true)
    yield
  rescue SignalException => e
    stop(pid, e.signo, group:)
    raise
  end

  # The signal first, then SIGKILL after the grace period, then the reap.
  def stop(pid, signo, group: true)
    target = group ? -pid : pid
    begin
      Process.kill(signo, target)
    rescue Errno::ESRCH, Errno::EPERM
      return reap(pid)
    end
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + STOP_GRACE_SEC
    until reap(pid, Process::WNOHANG)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        group ? kill_group(pid) : kill_one(pid)
        return reap(pid)
      end
      sleep 0.02
    end
  end

  def kill_one(pid)
    Process.kill("KILL", pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  # The child's status, nil while it runs, and true once another waiter (Open3's
  # own thread) has already reaped it.
  def reap(pid, flags = 0)
    Process.wait2(pid, flags)
  rescue Errno::ECHILD
    true
  end
end

# One way to ask ffmpeg for a measurement, for the scoring modules.
#
# They each interpolated the path into backticks, discarded the exit status and
# read the number with `.to_f`. A crate path holding a quote became a command, a
# hung decode blocked the caller forever, and a failed run printed no match, so
# `nil.to_f` reported 0.0 dB: silence, or a loudness 19 dB under target, from a
# file ffmpeg never opened. A measurement that cannot fail cannot be trusted.
module FfmpegProbe
  class Error < StandardError; end

  TIMEOUT = Integer(ENV.fetch("DILLA_PROBE_TIMEOUT", "300"))

  module_function

  # ffmpeg's log for `-af filter` run over path into the null muxer. Argument
  # vector, not a shell string; raises on a non-zero exit or the timeout.
  def run(path, filter, timeout: TIMEOUT)
    execute(["ffmpeg", "-nostdin", "-v", "info", "-i", path.to_s, "-af", filter, "-f", "null", "-"], path, timeout:)
  end

  # Seconds of audio in path, from ffprobe. A file ffprobe cannot read raises
  # rather than lasting zero seconds.
  def duration(path, timeout: TIMEOUT)
    out = execute(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path.to_s],
                  path, timeout:)
    number(out, /\A\s*([\d.]+)/, what: "duration")
  end

  # ebur128's summary block. The filter also prints a running I, LRA and peak
  # for every frame unless framelog=quiet is set, and the first of those is the
  # opening instant of the file -- -70 LUFS on anything that fades in. Anchored
  # to the summary headings, the reading is the summary whatever the filter's
  # options were. Values absent from the log are nil.
  def ebur128_summary(log)
    { i: log[/Integrated loudness:\s*\n\s*I:\s*(-?[\d.]+)/m, 1]&.to_f,
      lra: log[/Loudness range:\s*\n\s*LRA:\s*(-?[\d.]+)/m, 1]&.to_f,
      tp: log[/True peak:\s*\n\s*Peak:\s*(-?[\d.]+)/m, 1]&.to_f }
  end

  # loudnorm's print_format=json measurement, as a hash with string keys, or
  # an empty hash when the log holds none.
  def loudnorm_json(log)
    json = log[/\{\s*"input_i".*?\}/m]
    json ? JSON.parse(json) : {}
  rescue JSON::ParserError
    {}
  end

  # volumedetect's mean and max in dB; nil for one the log does not hold.
  def volumedetect(log)
    { mean: log[/mean_volume:\s*(-?[\d.]+)/, 1]&.to_f, max: log[/max_volume:\s*(-?[\d.]+)/, 1]&.to_f }
  end

  def execute(argv, path, timeout:)
    log, status = ToolRun.capture2e(*argv, timeout:)
    raise Error, "#{argv.first} timed out after #{timeout}s on #{path}" if status.signaled?
    raise Error, "#{argv.first} exited #{status.exitstatus} on #{path}: #{log.lines.last(2).join.strip}" unless status.success?

    log
  rescue Errno::ENOENT
    raise Error, "#{argv.first} is not installed or not on PATH"
  end

  # The float the pattern's first group captures, or Error when it is absent.
  def number(log, pattern, what:)
    raw = log[pattern, 1]
    raise Error, "no #{what} in ffmpeg output" if raw.nil?

    raw.to_f
  end
end

# Scores a render's MIX, not its harmony.
#
# beauty_report already scores chords. Nothing scored the thing that actually
# decided which tracks survived: whether the kick sits right against the mids,
# whether the track has any dynamics left, whether the top is harsh. Every one
# of those judgements this engine's operator made by ear had a number behind it
# that was computed by hand and then thrown away.
#
# The targets are not invented. They are measured from tracks that were kept
# after listening, which is the only defensible source for a "should sound like"
# number -- a threshold picked in advance measures the person who picked it.

module MixScore
  # Measured from demo29 and demo30, the two renders kept on their merits.
  # Ranges span both plus a little tolerance, rather than averaging them into a
  # single value neither actually has.
  REFERENCE = {
    kick_vs_mid: { range: (2.0..6.0), unit: "dB",
                   why: "kick against the midrange; demo29 +4.7, demo30 +3.0" },
    lufs: { range: (-18.0..-15.0), unit: "LUFS",
            why: "integrated loudness; both keepers near -16.5" },
    lra: { range: (4.0..9.0), unit: "LU",
           why: "loudness range; keepers 6.0 and 7.0. Below 3 is flat" },
    # Derived from the keepers like the rest, after the first attempt was
    # invented instead. I guessed -14..-4 on the reasoning that sub above -4
    # would mask the mids; demo29 measures +3.3 and demo30 +1.5, so the guess
    # was wrong and the tracks were right. This is precisely the failure the
    # comment at the top of this file warns about, committed by the person who
    # wrote the warning, one field after writing it.
    sub_vs_mid: { range: (0.0..5.5), unit: "dB",
                  why: "sub against mids; demo29 +3.3, demo30 +1.5" },
    cymbal_crest: { range: (18.0..30.0), unit: "dB",
                    why: "peak minus mean above 6k; low means smeared, high means spiky" },
    tilt: { range: (14.0..26.0), unit: "dB",
            why: "lows minus highs; high is dull, low is harsh" },
  }.freeze

  module_function

  def band(path, lo, hi, stat = :mean)
    key = stat == :peak ? "max_volume" : "mean_volume"
    log = FfmpegProbe.run(path, "highpass=f=#{lo},lowpass=f=#{hi},volumedetect")
    FfmpegProbe.number(log, /#{key}: ([-0-9.]+)/, what: key)
  end

  def loudness(path)
    log = FfmpegProbe.run(path, "ebur128=framelog=quiet")
    [FfmpegProbe.number(log, /I:\s*([-0-9.]+)/, what: "integrated loudness"),
     FfmpegProbe.number(log, /LRA:\s*([-0-9.]+)/, what: "loudness range")]
  end

  def measure(path)
    i, lra = loudness(path)
    mids = band(path, 400, 3000)
    cym = band(path, 6000, 14_000)
    {
      kick_vs_mid: (band(path, 40, 110) - mids).round(2),
      lufs: i.round(2),
      lra: lra.round(2),
      sub_vs_mid: (band(path, 20, 60) - mids).round(2),
      cymbal_crest: (band(path, 6000, 14_000, :peak) - cym).round(2),
      tilt: (band(path, 40, 400) - band(path, 5000, 14_000)).round(2),
    }
  end

  # Distance from the acceptable range, zero when inside it. Reported rather
  # than reduced to a single score: a track that is 6 dB off on one axis and
  # perfect elsewhere is a different problem from one slightly off on all six,
  # and a single number hides which.
  def score(path)
    m = measure(path)
    m.map do |key, value|
      spec = REFERENCE.fetch(key)
      r = spec[:range]
      miss =
        if value < r.begin then (value - r.begin).round(2)
        elsif value > r.end then (value - r.end).round(2)
        else 0.0
        end
      [key, value, miss, spec]
    end
  end

  def report(path)
    unless File.file?(path)
      warn "mix score: no such file #{path}"
      return false
    end

    rows = score(path)
    puts "  #{File.basename(path)}"
    puts format("  %-14s %9s %11s %8s  %s", "measure", "value", "target", "miss", "")
    rows.each do |key, value, miss, spec|
      r = spec[:range]
      puts format("  %-14s %9.2f %11s %8s  %s",
                  key, value, "#{r.begin}..#{r.end}",
                  miss.zero? ? "ok" : format("%+.2f", miss),
                  miss.zero? ? "" : spec[:why])
    end
    off = rows.count { |r| !r[2].zero? }
    puts
    puts off.zero? ? "  in range on all #{rows.size} measures" : "  #{off} of #{rows.size} outside the reference"
    off.zero?
  end

  # Compare two files directly, for A/B where the reference is another render
  # rather than the stored ranges.
  def compare(a, b)
    ma = measure(a)
    mb = measure(b)
    puts format("  %-14s %10s %10s %9s", "measure", File.basename(a, ".*")[0, 10],
                File.basename(b, ".*")[0, 10], "delta")
    ma.each_key do |k|
      puts format("  %-14s %10.2f %10.2f %+9.2f", k, ma[k], mb[k], mb[k] - ma[k])
    end
  end
end

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
    run("-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.5:duration=#{seconds}:r=#{RATE}:seed=5",
        "-ac", "2", path)
    path
  end

  # Two uncorrelated channels, for anything that claims to act on stereo width.
  def wide(path, seconds: 3)
    run("-filter_complex",
        "anoisesrc=color=pink:amplitude=0.5:duration=#{seconds}:r=#{RATE}:seed=5[l];" \
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
        "anoisesrc=color=pink:amplitude=0.9:duration=#{seconds}:r=#{RATE}:seed=5[l];" \
        "anoisesrc=color=brown:amplitude=0.9:duration=#{seconds}:r=#{RATE}:seed=11[r];" \
        "[l][r]join=inputs=2:channel_layout=stereo[o]",
        "-map", "[o]", path)
    path
  end

  def run(*args)
    ToolRun.system("ffmpeg", "-v", "error", "-y", *args.map(&:to_s), out: File::NULL, err: File::NULL)
  end

  def measure(path, af)
    FfmpegProbe.number(FfmpegProbe.run(path, af), /mean_volume: ([-0-9.]+)/, what: "mean_volume")
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
        rescue StandardError # ArgumentError is one of these
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

require "json"
require "open3"
require "fileutils"

# Spectral audit for rendered tracks.
#
# The engine already writes <track>.quality.json with integrated LUFS, true
# peak and a harmony score. None of those can see a spectral problem: a track
# whose top end has been filtered away, one with a resonant honk, or one that
# has collapsed to mono all measure exactly as loud as a good one. Loudness
# says how much, not what.
#
# So this measures shape rather than level, and writes a spectrogram alongside
# so the numbers can be checked by eye rather than taken on trust.
#
# Per track:
#   * band energy in dB across seven bands, so "no air" or "mud" is a number
#   * spectral centroid and rolloff, averaged over the whole file
#   * crest factor, DC offset, clipped-sample count
#   * stereo correlation — 1.0 means the render is effectively mono
#   * what a mono fold loses, and the side energy left under 120 Hz
#   * a PNG spectrogram
module SpectralAudit
  # Bands chosen for what goes wrong in this engine specifically: sub for the
  # kick, low_mid for the mud a sampled loop brings, presence for whether the
  # top survived the chain, air for whether a lowpass ate it.
  BANDS = {
    "sub" => [20, 60],
    "low" => [60, 250],
    "low_mid" => [250, 800],
    "mid" => [800, 2500],
    "presence" => [2500, 6000],
    "high" => [6000, 12_000],
    "air" => [12_000, 20_000],
  }.freeze

  module_function

  # ffmpeg writes its filter reports to stderr, so both streams matter. Reading
  # stdout alone is why the first run of this returned -120dB for every band:
  # the numbers were there, on the other stream.
  def sh(*cmd)
    out, err, _status = ToolRun.capture3(*cmd)
    [out, err].join("\n")
  end

  def ffprobe_duration(path)
    sh("ffprobe", "-v", "error", "-show_entries", "format=duration",
       "-of", "default=nw=1:nk=1", path).strip.to_f
  end

  # Mean of a per-frame aspectralstats metadata key across the file.
  def spectral_means(path)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             "-af", "aspectralstats=measure=centroid+rolloff+flatness,ametadata=print:file=-",
             "-f", "null", "-")
    acc = Hash.new { |h, k| h[k] = [] }
    raw.each_line do |line|
      next unless line =~ /aspectralstats\.\d+\.(\w+)=([\d.eE+-]+)/

      value = Regexp.last_match(2).to_f
      acc[Regexp.last_match(1)] << value if value.finite?
    end
    acc.transform_values { |vals| vals.empty? ? nil : (vals.sum / vals.size).round(1) }
  end

  # RMS inside one band, in dBFS. Band-limit with a steep filter, then measure.
  def band_db(path, low, high)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             # highpass/lowpass cap at 2 poles; chaining two gives the steeper
             # skirt a band measurement needs without ffmpeg rejecting p=4.
             "-af", "highpass=f=#{low}:p=2,highpass=f=#{low}:p=2," \
                    "lowpass=f=#{high}:p=2,lowpass=f=#{high}:p=2,astats",
             "-f", "null", "-")
    m = raw[/RMS level dB:\s*(-?[\d.]+|-inf)/, 1]
    return -120.0 if m.nil? || m == "-inf"

    m.to_f.round(1)
  end

  def time_stats(path)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             "-af", "astats",
             "-f", "null", "-")
    {
      "dc_offset" => raw[/DC offset:\s*(-?[\d.]+)/, 1]&.to_f&.round(4),
      "crest_factor" => raw[/Crest factor:\s*([\d.]+)/, 1]&.to_f&.round(2),
    }
  end

  # 1.0 = identical channels (mono). Below ~0.2 suggests phase trouble.
  def stereo_correlation(path)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             "-af", "astats=measure_overall=none:measure_perchannel=none,aphasemeter=video=0:phasing=0",
             "-f", "null", "-")
    vals = raw.scan(/lavfi\.aphasemeter\.phase=([\d.-]+)/).flatten.map(&:to_f)
    return nil if vals.empty?

    (vals.sum / vals.size).round(3)
  end

  # Overall RMS in dBFS after a filter chain, with -120 standing for silence.
  def rms_db(path, chain)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             "-af", "#{chain},astats=measure_perchannel=none",
             "-f", "null", "-")
    m = raw[/RMS level dB:\s*(-?[\d.]+|-inf)/, 1]
    m.nil? || m == "-inf" ? -120.0 : m.to_f
  end

  MID = "pan=mono|c0=0.5*c0+0.5*c1"
  SIDE = "pan=mono|c0=0.5*c0-0.5*c1"
  LOW_HZ = 120

  # What a mono playback loses, and how much of the low end is out of phase.
  #
  # Correlation is one number for the whole band, so a wide, decorrelated top
  # can sit beside a bass that cancels on a phone speaker or a club's mono sub
  # and the average reads healthy. mono_fold_loss_db is the level the mid
  # channel gives up against the stereo file: 0 for a mono render, about 3 for
  # uncorrelated channels, and large when the channels cancel.
  # low_side_to_mid_db is the side energy under LOW_HZ against the mid energy
  # there, which is the part a mono-bass stage is meant to remove. Both are
  # reported, not judged: neither has a threshold measured from a kept take.
  def mono_fold(path)
    stereo = rms_db(path, "anull")
    mid = rms_db(path, MID)
    low = "lowpass=f=#{LOW_HZ}:p=2,lowpass=f=#{LOW_HZ}:p=2"
    {
      "mono_fold_loss_db" => (stereo - mid).round(1),
      "low_side_to_mid_db" => (rms_db(path, "#{SIDE},#{low}") - rms_db(path, "#{MID},#{low}")).round(1),
    }
  end

  def spectrogram(path, out_png)
    FileUtils.mkdir_p(File.dirname(out_png))
    sh("ffmpeg", "-y", "-hide_banner", "-nostats", "-i", path,
       "-lavfi", "showspectrumpic=s=1200x480:mode=combined:legend=1:scale=log:color=intensity",
       out_png)
    File.file?(out_png) ? out_png : nil
  end

  def analyse(path, png_dir)
    name = File.basename(path)
    bands = BANDS.to_h { |label, (lo, hi)| [label, band_db(path, lo, hi)] }
    spec = spectral_means(path)
    {
      "track" => name,
      "duration_s" => ffprobe_duration(path).round(1),
      "bands_db" => bands,
      "centroid_hz" => spec["centroid"],
      "rolloff_hz" => spec["rolloff"],
      "flatness" => spec["flatness"],
      "stereo_correlation" => stereo_correlation(path),
      "spectrogram" => spectrogram(path, File.join(png_dir, "#{name}.png")),
    }.merge(time_stats(path)).merge(mono_fold(path))
  end

  # Findings are stated as thresholds with the number attached, so a
  # disagreement is about the threshold rather than about whether it happened.
  def findings(row)
    out = []
    b = row["bands_db"]
    out << "no air: #{b['air']}dB above 12k (>=25dB below presence #{b['presence']}dB) — top end filtered away" if
      b["air"] && b["presence"] && (b["presence"] - b["air"]) >= 25
    # No rolloff-based "dark" rule. rolloff is the 85%-of-energy point, so any
    # bass-heavy render lands under 2kHz however much top end it has: the first
    # version of this flagged a drum track as "energy dies below 2k" while its
    # spectrogram showed content all the way to 20k. Rolloff is reported as
    # context, not judged. Whether the top survived is the air/presence gap
    # below, which is a shape comparison and does not care about bass weight.
    out << "mud: low_mid #{b['low_mid']}dB sits #{(b['low_mid'] - b['mid']).round(1)}dB over mid" if
      b["low_mid"] && b["mid"] && (b["low_mid"] - b["mid"]) > 9
    out << "effectively mono: correlation #{row['stereo_correlation']}" if
      row["stereo_correlation"] && row["stereo_correlation"] > 0.98
    out << "DC offset #{row['dc_offset']}" if row["dc_offset"] && row["dc_offset"].abs > 0.01
    out << "crest #{row['crest_factor']} — heavily compressed" if
      row["crest_factor"] && row["crest_factor"] < 3.0
    out
  end
end

# Run over every rendered track and print the table. `ruby lib/listen.rb
# [out_dir]` — the runner that did this was a second file whose only caller was
# the usage line in its own header.
if $PROGRAM_NAME == __FILE__
  root = File.expand_path("..", __dir__)
  # Renders sit beside dilla.rb, so the audit reads them there. Its images and
  # table are disposable, so they go to scratch/ rather than to a new folder.
  out_dir = ARGV[0] || File.join(root, "scratch")
  tracks = Dir[File.join(root, "*.mp3")].sort

  abort "no tracks found under #{root}" if tracks.empty?

  rows = tracks.map do |path|
    row = SpectralAudit.analyse(path, out_dir)
    row["findings"] = SpectralAudit.findings(row)
    warn format("%-46s centroid %6s  air %6s  crest %5s  %s",
                row["track"][0, 46], row["centroid_hz"], row["bands_db"]["air"],
                row["crest_factor"], row["findings"].empty? ? "ok" : row["findings"].size.to_s + " finding(s)")
    row
  end

  File.write(File.join(out_dir, "spectral_audit.json"), JSON.pretty_generate(rows))

  puts "\n=== #{rows.size} track(s) ==="
  flagged = rows.reject { |r| r["findings"].empty? }
  puts "clean: #{rows.size - flagged.size}   flagged: #{flagged.size}"
  flagged.each do |r|
    puts "\n#{r['track']}"
    r["findings"].each { |f| puts "  - #{f}" }
  end

  # Outliers matter more than absolutes here: these are all meant to be one
  # catalogue, so a track sitting far from its siblings is the signal.
  centroids = rows.filter_map { |r| r["centroid_hz"] }
  if centroids.size > 2
    mean = centroids.sum / centroids.size
    sd = Math.sqrt(centroids.sum { |c| (c - mean)**2 } / centroids.size)
    puts "\n=== centroid spread: mean #{mean.round} Hz, sd #{sd.round} Hz ==="
    rows.each do |r|
      c = r["centroid_hz"]
      next unless c && sd.positive? && ((c - mean).abs / sd) > 1.8

      puts format("  %-46s %6.0f Hz (%+.1f sd)", r["track"][0, 46], c, (c - mean) / sd)
    end
  end
  puts "\nspectrograms + spectral_audit.json in #{out_dir}"
end
