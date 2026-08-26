# frozen_string_literal: true

require "yaml"
require "open3"

# Mastering/mix heuristics — harshness, club IR, phone preview, cassette, balance.
# Multi-persona critique + multi-solution cherry-pick live in MASTER council:
#   /sound-critique  and  /dilla crit
# Do not reimplement Council::Critique / Ideation here.
module DillaMaster
  IR_DIR = File.join(File.expand_path("..", __dir__), "samples", "irs")
  REFERENCE_PATH = File.expand_path("../dilla_reference.yml", __dir__)

  module_function

  def enabled?
    ENV["MASTER_HEURISTICS"] == "1"
  end

  def loss_gates
    return {} unless File.file?(REFERENCE_PATH)

    YAML.safe_load_file(REFERENCE_PATH)["loss_gates"] || {}
  rescue StandardError, Psych::Exception
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
    out, = Open3.capture2(
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
    out, = Open3.capture2(
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
    system("ffmpeg", "-y", "-i", path, "-af", phone_preview_chain, "-c:a", "pcm_s16le", tmp)
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
