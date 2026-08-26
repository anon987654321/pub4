# frozen_string_literal: true
#
# Running external tools: ffmpeg, fluidsynth, demucs, playback.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Per-tool wall-clock cap. Hang-prone fluidsynth/ffmpeg used to block stream
# forever (waitpid with no timeout). Override: DILLA_SH_TIMEOUT=180.
def sh_timeout_sec
  sec = (ENV["DILLA_SH_TIMEOUT"] || "120").to_i
  sec.positive? ? sec : 120
end

# Spawn in its own process group so timeout can kill children (ffmpeg forks).
def system_with_timeout(argv, timeout_sec:, verbose: false)
  err_path = File.join(Dir.tmpdir, "dilla_sh_#{Process.pid}_#{rand(0x100000)}.err")
  out_opt = verbose ? :out : File::NULL
  err_file = File.open(err_path, "w")
  pid = nil
  begin
    # in: File::NULL — pgroup:true detaches the child from the terminal's
    # foreground group, so a tool that polls stdin (ffmpeg's interactive 'q'
    # reader) takes SIGTTIN and sits STOPPED until the timeout kills it.
    # That serially killed every stream track at exactly 120s.
    pid = spawn(*argv, in: File::NULL, out: out_opt, err: err_file, pgroup: true)
  rescue StandardError
    # spawn raises before anything is returned when the binary is missing
    # (Errno::ENOENT), so err_path never reaches sh!, which is the only thing
    # that removes it. An `ensure` at the foot of the method holding a comment
    # and no code removes nothing, and leaves every failed spawn's
    # dilla_sh_*.err file in the temp directory for good.
    FileUtils.rm_f(err_path)
    raise
  ensure
    err_file.close
  end
  status = nil
  begin
    Timeout.timeout(timeout_sec) do
      _pid, status = Process.wait2(pid)
    end
  rescue Timeout::Error
    begin
      Process.kill("-KILL", pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
    begin
      Process.wait2(pid)
    rescue Errno::ECHILD
      nil
    end
    return [false, "timeout after #{timeout_sec}s", err_path]
  end
  # err_path is handed back, not removed here: sh! reads the tail for its
  # diagnostic line and then removes it on both the success and failure paths.
  ok = status&.success?
  err_tail = File.readable?(err_path) ? File.read(err_path).to_s.lines.last(12).join : ""
  [ok, err_tail, err_path]
end

def sh!(*command)
  argv = command.flatten.map(&:to_s)
  display = argv.join(" ")
  display = "#{display.byteslice(0, 420)}… (#{display.bytesize} bytes)" if display.bytesize > 460
  bin = File.basename(argv.first.to_s)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ok = false
  err_tail = ""
  err_path = nil
  if DillaDmesg.interactive_bin?(argv)
    DillaDmesg.play!(bin, argv.last.to_s) if argv.length > 1
    ok = system(*argv)
  else
    ok, err_tail, err_path = system_with_timeout(
      argv,
      timeout_sec: sh_timeout_sec,
      verbose: DillaDmesg.verbose?,
    )
  end
  sec = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  exitstatus = ok ? 0 : ($?.respond_to?(:exitstatus) && $?.exitstatus) || 1
  DillaDmesg.run!(display, exitstatus:, seconds: sec)
  if ok
    FileUtils.rm_f(err_path) if err_path
    return
  end
  if err_tail && !err_tail.strip.empty?
    # The LAST lines, and the diagnostic ones by preference.
    #
    # This printed the first three lines of the captured tail, which for ffmpeg
    # are always the input stream dump -- sample rate, channel layout, bitrate.
    # The line that says what went wrong is the last one. Every failed render
    # this session reported "duration: n/a, bitrate: 2822 kb/s" and nothing
    # about the fault, so each one had to be diagnosed by rebuilding the
    # filtergraph by hand.
    lines = err_tail.lines.map(&:strip).reject(&:empty?)
    blamed = lines.grep(/error|invalid|no such|cannot|unable|matches no|not connected|deadlock/i)
    shown = blamed.empty? ? lines.last(3) : blamed.last(3)
    dmesg_warn("#{bin} stderr: #{shown.join(' | ')}")
  end
  msg = err_tail.to_s.include?("timeout after") ? "timeout: #{bin}" : "failed: #{bin}"
  dmesg_error(msg)
  FileUtils.rm_f(err_path) if err_path
  raise RuntimeError, msg if ENV["DILLA_STREAMING"] == "1" || ENV["DILLA_SOFT_SH"] == "1"
  abort msg
end

# ffmpeg takes an entire filtergraph as ONE argv entry, and the native
# synth graphs grow with the note count -- one aevalsrc per note. At 32 bars
# (the stream's own default length) the xlead graph crossed the OS argument
# limit and spawn raised Errno::E2BIG, so every 32-bar render died partway
# through while 8-bar renders passed and looked fine. -filter_complex_script
# reads the identical graph from a file instead, which has no such ceiling.
FILTER_GRAPH_ARG_LIMIT = 60_000

def sh_filter_complex!(graph, *args)
  return sh!("ffmpeg", "-y", "-filter_complex", graph, *args) if graph.bytesize < FILTER_GRAPH_ARG_LIMIT

  script = dilla_render_tmp("fgraph_#{Process.pid}_#{graph.bytesize}.txt")
  File.write(script, graph)
  dmesg("filtergraph #{(graph.bytesize / 1024.0).round}KB via script file", unit: "exec0", parent: "dilla0")
  begin
    sh!("ffmpeg", "-y", "-filter_complex_script", script, *args)
  ensure
    FileUtils.rm_f(script)
  end
end

# Every offline fluidsynth render goes through here, so a setting can be added
# in one place instead of the eight that spelled this argv by hand.
#
# fluidsynth's own chorus and reverb are ON by default and this engine's gains
# were tuned with them on. Rendering a six-note sustained pad through
# GeneralUser-GS with `-o synth.chorus.active=0 -o synth.reverb.active=0`
# measures 12.6 dB less side-channel energy (side RMS -32.9 dB -> -45.6 dB) and
# -0.4 LUFS: the pad arrives at the bus close to mono. Defensible -- the engine
# has its own space and width stages -- but that is a sound change, not an
# optimisation, so it is opt-in rather than a default. It buys ~90 ms of a
# ~450 ms call, against ffmpeg stages that dominate the render.
#
# Polyphony stays at fluidsynth's 256 default. GM presets spend two to four
# voices per note, so a 96-voice cap is 24-48 sustained notes, and voice
# stealing is silent -- nothing downstream would catch a pad losing notes.
def fluidsynth_render!(out_path, sf2, midi_path, gain:)
  dry = if ENV["DILLA_FS_DRY"] == "1"
          ["-o", "synth.chorus.active=0", "-o", "synth.reverb.active=0"]
        else
          []
        end
  sh! "fluidsynth", "-ni", "-g", gain.to_s, *dry,
      "-F", out_path.to_s, "-r", SAMPLE_RATE.to_s, sf2.to_s, midi_path.to_s
end

def capture(*command)
  Open3.capture3(*command.flatten.map(&:to_s))
end

def tool_available?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |directory| File.executable?(File.join(directory, name)) }
end

# One definition. There were two -- one beside the mix metrics, one beside the
# pad layers -- and Ruby does not warn when a second `def` of the same name
# replaces the first, so whichever file loaded last silently owned the method
# for every caller in the engine. They agreed on the answer, which is the only
# reason this was invisible rather than a bug: both shell out to ffprobe and
# both return 0.0 when it is absent, one by guarding and one by rescuing.
#
# Here rather than in either caller, next to the tool guard and the shell
# wrapper it is built from, and keeping both of the answers they gave: the
# guard, so a missing ffprobe is not an exception, and the rescue, so a file
# ffprobe cannot read is not either.
def audio_duration_sec(path)
  return 0.0 unless tool_available?("ffprobe")

  out, = capture("ffprobe", "-v", "error", "-show_entries", "format=duration",
                 "-of", "default=noprint_wrappers=1:nokey=1", path)
  out.to_s.strip.to_f
rescue StandardError
  0.0
end

DEMUX_VENV_PYTHON = File.join(DEMUX_VENV_DIR, "bin", "python").freeze

def demucs_cmd
  return %w[demucs] if tool_available?("demucs")
  return [DEMUX_VENV_PYTHON, "-m", "demucs"] if File.executable?(DEMUX_VENV_PYTHON) &&
                                                  system(DEMUX_VENV_PYTHON, "-m", "demucs", "--help",
                                                         out: File::NULL, err: File::NULL)
  return %w[python3 -m demucs] if system("python3", "-m", "demucs", "--help", out: File::NULL, err: File::NULL)
  nil
end

def demucs_available?
  !demucs_cmd.nil?
end

# One dependency gate for every external binary — reports all missing tools
# at once instead of failing on the first and hiding the rest.
def require_tools!(*names)
  missing = names.reject { |name| tool_available?(name) }
  return if missing.empty?
  abort "#{missing.join(', ')} required"
end

def darwin?
  RUBY_PLATFORM.include?("darwin")
end

# ffplay from agent/nohup shells often has no CoreAudio route on macOS;
# afplay uses the logged-in user's default output device.
def playback_tool
  return "afplay" if darwin? && tool_available?("afplay")
  return "ffplay" if tool_available?("ffplay")
  nil
end

def require_playback_tool!
  abort "afplay or ffplay required" unless playback_tool
end

def ensure_mac_output_audible!
  return unless darwin?
  return if ENV["SKIP_VOLUME_NUDGE"] == "1"
  # Unmute + raise output if the session is silent (common “I can’t hear” cause).
  system("osascript", "-e",
         "set volume output volume 70 without output muted",
         out: File::NULL, err: File::NULL)
rescue StandardError
  nil
end

def play_audio(path, loop: false)
  tool = playback_tool
  unless tool
    msg = "afplay or ffplay required"
    raise RuntimeError, msg if ENV["DILLA_STREAMING"] == "1"
    abort msg
  end
  abort "missing audio #{path}" unless path && File.file?(path)
  ensure_mac_output_audible!
  vol = (ENV["PLAY_VOL"] || "1").to_f.clamp(0.0, 1.0)
  dmesg("play #{File.basename(path)} vol=#{vol} tool=#{tool} size=#{File.size(path)}",
        unit: "play0", parent: "dilla0")
  case tool
  when "afplay"
    if loop
      dmesg("loop #{File.basename(path)} via afplay (ctrl-c stop)", unit: "play0", parent: "dilla0")
      trap("INT") { exit 0 }
      loop { sh! "afplay", "-v", format("%.3f", vol), path }
    else
      sh! "afplay", "-v", format("%.3f", vol), path
    end
  else
    args = ["ffplay", "-nodisp", "-volume", (vol * 100).round.to_s]
    args << (loop ? "-loop" : "-autoexit")
    args << "0" if loop
    sh!(*args, path)
  end
end

def prompt(label)
  print "#{label}: "
  value = STDIN.gets&.strip
  abort "missing #{label}" if value.nil? || value.empty?
  value
end

# --- FFmpeg expression helpers ---

def lavfi(src)
  ["-f", "lavfi", "-i", src]
end

# Sum ffmpeg aeval expressions; never return empty (ffmpeg rejects blank expr).
def expr_sum(parts)
  flat = parts.flatten.compact.reject { |p| p.to_s.strip.empty? }
  flat.empty? ? "0" : flat.join("+")
end

# Wrap volume envelope for noise-channel gating (snare/hat/open).
def safe_volume_env(parts)
  "(#{expr_sum(parts)})"
end

def chop_hz(chord, t = 0.0)
  raw = case chord
        when Hash  then chord[:hz] || chord["hz"] || []
        when Array then chord
        else []
        end
  return raw if raw.empty? || !defined?(DillaSpectral) || !DillaSpectral.enabled?
  DillaSpectral.chop_hz(chord.is_a?(Hash) ? chord : { hz: raw }, t)
end

# Sample-chop wave: chord may be a PAD_CHORDS Hash or raw Hz array.
def chop_wave(chord, t, v, sustain = 0.55)
  hz = chop_hz(chord)
  return "0" if hz.empty?
  f = hz[(t * 10).to_i % hz.length]
  "between(t,#{t},#{t + sustain})*#{v}*0.11*exp(-(t-#{t})*1.7)*" \
    "(sin(2*PI*#{f}*(t-#{t}))+0.35*sin(2*PI*#{f * 1.5}*(t-#{t})))"
end

def bpm
  # Scaled like resolve_bpm's, or this helper and cfg[:bpm] would disagree about
  # the tempo of the same render.
  ((ENV["BPM"] || DEFAULT_BPM).to_f * bpm_scale).round(2)
end

def bars
  (ENV["BARS"] || DEFAULT_BARS).to_i
end

def beat_seconds
  60.0 / bpm
end

def render_seconds
  (beat_seconds * 4.0 * bars).round(3)
end

def chord_expression
  cycle = (PAD_CHORDS.length * 8.0 * beat_seconds).round(4)
  PAD_CHORDS.each_with_index.map do |chord, chord_index|
    start_seconds = chord_index * 8.0 * beat_seconds
    stop_seconds = start_seconds + 8.0 * beat_seconds
    voices = chord[:hz].each_with_index.map do |frequency, voice_index|
      detune = 1.0 + ((voice_index - 2) * 0.0015)
      gain = 0.018 + (voice_index * 0.002)
      "#{gain.round(4)}*sin(2*PI*#{(frequency * detune).round(4)}*t)"
    end.join("+")
    "between(mod(t,#{cycle}),#{start_seconds.round(4)},#{stop_seconds.round(4)})*(#{voices})"
  end.join("+")
end

def start_groove_preview
  return unless tool_available?("ffplay")

  tmp = File.join(SCRATCH_DIR, "groove_tmp.wav")
  render_dilla(tmp, [8, bars].max)
  pid = spawn("ffplay", "-nodisp", "-loop", "0", tmp, out: "/dev/null", err: "/dev/null")
  [pid, tmp]
rescue SystemCallError
  nil
end
