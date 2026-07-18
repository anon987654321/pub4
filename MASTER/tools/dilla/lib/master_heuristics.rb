# frozen_string_literal: true

# Mastering/mix heuristics — harshness, club IR, phone preview, cassette, balance.
module DillaMaster
  IR_DIR = File.join(File.expand_path("..", __dir__), "samples", "irs")

  module_function

  def enabled?
    ENV["MASTER_HEURISTICS"] == "1"
  end

  def club_ir_path
    return nil unless enabled?
    custom = ENV["CLUB_IR"]
    return custom if custom && File.file?(custom)
    File.join(IR_DIR, "club.wav") if File.file?(File.join(IR_DIR, "club.wav"))
  end

  def extra_filters(input_tag, cfg:, duration:, section_fn: nil)
    return [] unless enabled?
    out = []
    tag = "#{input_tag}_mh"
    chain = "[#{input_tag}]"
    chain += perceptual_limiter if ENV["PERCEPTUAL_LIMIT"] != "0"
    chain += harshness_notch if ENV["HARSHNESS_NOTCH"] != "0"
    chain += cassette_wow if ENV["CASSETTE_PRINT"] == "1"
    chain += radio_club_morph(cfg, duration, section_fn) if ENV["RADIO_CLUB_MORPH"] == "1"
    return [] if chain == "[#{input_tag}]"
    out << "#{chain}[#{tag}]"
    out
  end

  def perceptual_limiter
    ",alimiter=limit=0.92:level_out=0.94, equalizer=f=3500:t=o:w=1.2:g=-1.5"
  end

  def harshness_notch
    ",equalizer=f=4200:t=h:w=800:g=-2.5,equalizer=f=6800:t=h:w=1200:g=-1.8"
  end

  def cassette_wow
    ",vibrato=f=0.25:d=0.003,acrusher=bits=11:samples=2:mix=0.12"
  end

  def radio_club_morph(cfg, duration, _section_fn)
    mid = (duration * 0.5).round(2)
    ",volume='if(lt(t,#{mid}),0.92,1.08)':eval=frame"
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