# frozen_string_literal: true
#
# Mix measurement and the default render path.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# low/mid/high stay at their historical edges so sub_kick_balance and old
# quality sidecars keep the same numbers. body/presence/air are the three
# bands analyze_harshness actually needs (2 kHz and 4 kHz splits).
RENDER_SPECTRUM_BANDS = {
  low: [28, 180],
  body: [180, 2_000],
  mid: [180, 3_500],
  presence: [2_000, 4_000],
  high: [3_500, 16_000],
  air: [4_000, 16_000],
}.freeze

def render_spectrum(path)
  RENDER_SPECTRUM_BANDS.transform_values { |lo, hi| band_rms(path, highpass: lo, lowpass: hi) }
end

# Objective mix meters for piping into MASTER council (not a parallel critique stack).
# Persona panel, multi-solution ideation, and cherry-pick:
#   MASTER /dilla crit [path]  or  /dilla-critique  or  /sound-critique
MIX_METRIC_BANDS = {
  sub_db: [40, 100],
  pad_body_db: [100, 300],
  mids_db: [300, 1200],
  presence_db: [1200, 4000],
  air_db: [4000, 12_000],
}.freeze

# Analysis window, in seconds. Bounded on purpose, and the bound is reported
# back as analysed_sec rather than applied silently: three minutes is a fair
# sample of a mix's band balance, and a 47-minute set is not more truthful,
# only six full decodes more expensive. duration_sec still carries the real
# length so a reader can see both.
MIX_METRIC_WINDOW_SEC = Integer(ENV.fetch("DILLA_MIX_WINDOW_SEC", "180"))

# One asplit, six volumedetects, one decode — overall level plus every band.
# Six separate ffmpeg runs over demo.wav cost 29s; this costs 1.3s.
def mix_metric_command(path, window_sec)
  outlets = (0..MIX_METRIC_BANDS.size).map { |index| "[b#{index}]" }
  chains = ["[b0]#{BAND_FILTER_PREFIX},volumedetect[o0]"]
  MIX_METRIC_BANDS.each_value.with_index(1) do |(low, high), index|
    chains << "[b#{index}]highpass=f=#{low},lowpass=f=#{high},#{BAND_FILTER_PREFIX},volumedetect[o#{index}]"
  end
  maps = (0..MIX_METRIC_BANDS.size).flat_map { |index| ["-map", "[o#{index}]", "-f", "null", "-"] }
  ["ffmpeg", "-hide_banner", "-nostats", "-t", window_sec.to_s, "-i", path,
   "-filter_complex", "[0:a]asplit=#{outlets.size}#{outlets.join};#{chains.join(';')}", *maps]
end

# ffmpeg tags each filter instance with its position in the graph
# (`[Parsed_volumedetect_4 @ 0x…] mean_volume: -31.6 dB`) and prints the
# summaries in reverse order at teardown, so sort by that index rather than
# trusting the order of the lines.
def parse_volumedetect(log)
  readings = {}
  log.scan(/\[Parsed_volumedetect_(\d+)[^\]]*\]\s+(mean|max)_volume:\s*(-?[\d.]+)/) do |index, kind, value|
    (readings[index.to_i] ||= {})[kind.to_sym] = value.to_f
  end
  readings.keys.sort.map { |index| readings[index] }
end

# Objective mix meters for piping into MASTER council (not a parallel critique stack).
# Persona panel, multi-solution ideation, and cherry-pick:
#   MASTER /dilla crit [path]  or  /dilla-critique  or  /sound-critique
def mix_metrics(path)
  return unless path && File.file?(path)
  return unless tool_available?("ffmpeg")

  _out, error, status = capture(*mix_metric_command(path, MIX_METRIC_WINDOW_SEC))
  overall, *bands = status.success? ? parse_volumedetect(error.to_s) : []
  overall ||= {}
  peak_db = overall.fetch(:max, -90.0)
  rms_db = overall.fetch(:mean, -90.0)
  duration = audio_duration_sec(path)
  {
    peak_db:, rms_db:,
    crest: (peak_db > -80 && rms_db > -80) ? (10**((peak_db - rms_db) / 20.0)).round(3) : 0.0,
    duration_sec: duration.round(2),
    analysed_sec: (duration.positive? ? [duration, MIX_METRIC_WINDOW_SEC.to_f].min : MIX_METRIC_WINDOW_SEC.to_f).round(2),
    **MIX_METRIC_BANDS.keys.zip(bands.map { |band| band&.fetch(:mean, nil) || -Float::INFINITY }).to_h,
  }
end

def crit_session_cli!(path = nil)
  path ||= File.join(OUTPUT_DIR, "demo.wav")
  path = File.join(ROOT, "demo.wav") unless File.file?(path)
  abort "crit: missing #{path} — render first, then perfect via MASTER" unless File.file?(path)
  DillaDmesg.boot!(cmd: "crit")
  DillaDmesg.read!(path)
  m = mix_metrics(path)
  DillaDmesg.metrics!(m)
  puts JSON.pretty_generate(m)
  dmesg("meters only — multi-persona cherry-pick via master /dilla crit", unit: "meter0", parent: "dilla0")
  dmesg("master: /dilla crit #{File.basename(path)} or /dilla-critique", unit: "meter0", parent: "dilla0")
  abort "crit: unusable levels" if m[:peak_db].to_f > -0.2 || (m[:rms_db] && m[:rms_db] < -40)
  dmesg("meters ok — run master council to perfect", unit: "meter0", parent: "dilla0")
end

def render_quality_acceptable?(path)
  return true unless quality_gate_enabled?
  return true unless File.file?(path)
  chords = DillaHarmony.last_progression_chords
  beauty = DillaHarmony.score_beauty(chords)
  spectrum = render_spectrum(path)
  harsh = DillaMaster.analyze_harshness(spectrum)
  sk = DillaMaster.sub_kick_balance(spectrum, beauty)
  min_beauty = if ENV["DILLA_STREAMING"] == "1"
                 STREAM_BEAUTY_MIN
               else
                 (ENV["RENDER_BEAUTY_MIN"] || "70").to_f
               end
  beauty_ok = beauty >= min_beauty && !harsh[:needs_notch]
  # A band-limited source cannot be re-rendered into having low end.
  #
  # sub_kick_balance measures low-band minus mid-band dB, and a 78rpm transfer
  # sits about twelve down by construction — there was nothing below 200Hz on
  # the shellac to begin with. Feeding one in as SAMPLE_LOOP therefore failed
  # this gate on every take, and each retry re-rendered a mix whose deficiency
  # came from the source rather than from the mix, so the loop could not
  # converge: measured -12.67 dB, three retries a track, no audio for twenty
  # minutes. Retrying a render to fix the record it sampled is not a gate doing
  # its job, it is a gate asking the wrong question.
  #
  # So the deficit is attributed. If the bed is already past the threshold on
  # its own, the render did not cause it and cannot cure it; the gate says so
  # once and stops blocking. The engine's own bass still carries the low end,
  # and refine_deep_mix_env! still nudges PAD_VOL upward as it always did.
  sub_ok = !(deep_render? && sk[:recommendation] == "boost_sub" &&
             sk[:low_mid_delta].to_f < -9.0 && !sample_bed_band_limited?)
  ok = beauty_ok && sub_ok
  if ok && phone_preview_gate_enabled?
    phone_path = DillaMaster.apply_phone_preview!(path)
    phone_spec = render_spectrum(phone_path)
    phone = DillaMaster.phone_preview_acceptable?(phone_spec)
    unless phone[:ok]
      warn "phone preview gate: mid=#{phone[:mid_db]} dB, low-mid=#{phone[:low_mid_delta]} dB, " \
           "harsh=#{phone[:harshness]} — retrying"
      ok = false
    end
    FileUtils.rm_f(phone_path) if phone_path != path && phone_path.end_with?(".phone.wav")
  end
  unless ok
    unless beauty_ok
      warn "quality gate: beauty=#{beauty} (min #{min_beauty}), harsh=#{harsh[:harshness]} — retrying"
    end
    unless sub_ok
      warn "quality gate: sub=#{sk[:recommendation]} (low-mid #{sk[:low_mid_delta]} dB) — retrying"
    end
  end
  ok
end

def refine_deep_mix_env!(path)
  return unless File.file?(path)
  spectrum = render_spectrum(path)
  beauty = DillaHarmony.score_beauty(DillaHarmony.last_progression_chords)
  sk = DillaMaster.sub_kick_balance(spectrum, beauty)
  changed = false
  if sk[:recommendation] == "boost_sub"
    kg = [(ENV["KICK_GAIN"] || "0.34").to_f + 0.05, 0.48].min
    ENV["KICK_GAIN"] = kg.round(2).to_s
    changed = true
  elsif sk[:recommendation] == "reduce_sub"
    kg = [(ENV["KICK_GAIN"] || "0.34").to_f - 0.04, 0.12].max
    ENV["KICK_GAIN"] = kg.round(2).to_s
    changed = true
  end
  harm_w = (ENV["DEBUG_HARM_WEIGHT"] || "1.68").to_f
  if beauty < 72 && harm_w < 2.0
    ENV["DEBUG_HARM_WEIGHT"] = (harm_w + 0.12).round(2).to_s
    changed = true
  end
  changed
end

def log_render_meta(path)
  chords = DillaHarmony.last_progression_chords
  beauty = DillaHarmony.score_beauty(chords)
  patches = [@render_ep_patch&.dig(:id), @render_warm_patch&.dig(:id)].compact.join("/")
  # Same rule as the "wrote" line: don't name lead patches a silent render never used.
  leads = if lead_arp_enabled?
            [@render_scale_lead_patch&.dig(:id), @render_lead_patch&.dig(:id)].compact.join("+")
          else
            "off"
          end
  prog = chords&.map { |c| c[:name] }&.join(" → ")
  depth = deep_render? ? "deep" : "standard"
  puts "track=#{ENV['TRACK']} mode=#{depth} patches=#{patches || 'native'} pad_arp=#{pad_arp_mode} " \
       "leads=#{leads} beauty=#{beauty}"
  puts "progression: #{prog}" if prog
  puts "quality: ruby dilla.rb beauty #{path}" if File.file?(path)
end

def deep_default_render!(dest, n_bars)
  ensure_external_assets_lazy!
  retries = [(ENV["RENDER_RETRIES"] || "2").to_i, 0].max
  listen_passes = [(ENV["LISTEN_PASSES"] || "0").to_i, 0].max
  (retries + 1).times do |try|
    pick_render_seed! if try.positive?
    render_dilla(dest, n_bars)
    break if render_quality_acceptable?(dest)
    warn "deep render retry #{try + 1}/#{retries + 1}"
  end
  listen_passes.times do |pass|
    break unless refine_deep_mix_env!(dest)
    warn "deep mix refine pass #{pass + 1}/#{listen_passes}"
    pick_render_seed!
    render_dilla(dest, n_bars)
  end
  log_render_meta(dest)
  # Reported unless QUALITY_REPORT=0. Read-only: it measures the file that
  # was written and prints. A measurement nobody asked for is how a
  # drift gets noticed.
  dilla_quality(dest) if ENV["QUALITY_REPORT"] != "0" && File.file?(dest)
end

def default_render!(argv = ARGV)
  dest = if argv[0] && argv[0] =~ /\.(wav|mp3|flac|ogg|m4a|aiff?)\z/i
           argv.shift
         else
           DEFAULT_RENDER_OUTPUT
         end
  n_bars = argv[0]&.match?(/\A\d+\z/) ? argv.shift.to_i : nil
  FileUtils.mkdir_p(File.dirname(dest))
  if deep_render?
    deep_default_render!(dest, n_bars)
  else
    render_dilla(dest, n_bars)
  end
end
