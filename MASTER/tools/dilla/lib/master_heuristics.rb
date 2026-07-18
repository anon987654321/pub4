# frozen_string_literal: true

require "yaml"

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
  def passes_loss_gates?(report)
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
    if mud
      max = gates["mud_max_db_200_400hz"]
      failures << "mud #{mud.round(1)}dB > #{max}dB (200-400Hz masking snare body)" if max && mud > max
    else
      skipped << "mud_db_200_400hz (not measured by this engine yet)"
    end

    { pass: failures.empty?, failures: failures, skipped: skipped }
  end

  def club_ir_path
    return nil unless enabled?
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

  def radio_club_morph_parts(cfg, duration, _section_fn)
    mid = (duration.to_f * 0.5).round(2)
    [DillaAutomation.volume_filter([[0, 0.92], [mid, 1.08]])]
  end

  # Back-compat aliases (leading comma form is intentional for mid-chain append).
  def perceptual_limiter
    ",#{perceptual_limiter_parts.join(',')}"
  end

  def harshness_notch
    ",#{harshness_notch_parts.join(',')}"
  end

  def cassette_wow
    ",#{cassette_wow_parts.join(',')}"
  end

  def radio_club_morph(cfg, duration, section_fn = nil)
    ",#{radio_club_morph_parts(cfg, duration, section_fn).join(',')}"
  end

  def phone_preview_chain
    # mono output has only c0 — c1= is invalid on ffmpeg 8.x pan=mono
    "highpass=f=180,lowpass=f=3800,pan=mono|c0=0.5*c0+0.5*c1,alimiter=limit=0.9"
  end

  def analyze_harshness(spectrum)
    high = spectrum[:high] || spectrum["high"] || -30.0
    mid = spectrum[:mid] || spectrum["mid"] || -20.0
    delta = high.to_f - mid.to_f
    { harshness: delta.round(2), needs_notch: delta > 6.0 }
  end

  def sub_kick_balance(spectrum, harmony_score = nil)
    low = spectrum[:low] || spectrum["low"] || -18.0
    mid = spectrum[:mid] || spectrum["mid"] || -22.0
    ratio = low.to_f - mid.to_f
    rec = ratio < -8 ? "boost_sub" : ratio > 2 ? "reduce_sub" : "ok"
    rec = "boost_sub" if harmony_score && harmony_score < 65
    { low_mid_delta: ratio.round(2), recommendation: rec }
  end

  def groove_vinyl_level(ghost_count, kick_count)
    base = 0.06
    return base unless enabled? && ENV["GROOVE_VINYL"] != "0"
    g = ghost_count.to_f / [kick_count, 1].max
    (base + g * 0.015).clamp(0.04, 0.14).round(3)
  end

  def vocal_carve_placeholder?
    enabled? && ENV["VOCAL_CARVE"] == "1"
  end

  def vocal_carve_filter
    ",equalizer=f=2800:t=h:w=900:g=-2.2:enable='gte(t,0)'"
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
      ok: ok, mid_db: mid.round(2), low_mid_delta: low_mid.round(2),
      harshness: harsh[:harshness], needs_notch: harsh[:needs_notch]
    }
  end
end
