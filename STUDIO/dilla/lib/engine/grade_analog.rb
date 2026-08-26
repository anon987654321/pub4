# frozen_string_literal: true
#
# Grades, Sonitex tape presets and analog emulation chains.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- Analog grade engine ---

# Build an ffmpeg filter fragment for one grade effect using stock params.
# Each filter maps to a postpro analog concept (see GRADE_PRESETS comment).
def grade_filter(fx, stock)
  case fx
  when "tape_saturation"
    # H&D characteristic curve analog: tanh waveshaper, gain-neutral.
    d = stock[:sat_drive]
    n = Math.tanh(d).round(6)
    "aeval=exprs='tanh(#{d}*val(0))/#{n}|tanh(#{d}*val(1))/#{n}'"
  when "analog_noise"
    # Newson-Delon grain analog: flat Gaussian noise floor at stock amplitude.
    a = stock[:noise_amp]
    "aeval=exprs='val(0)+#{a}*(random(0)-0.5)|val(1)+#{a}*(random(1)-0.5)'"
  when "harmonic_bloom"
    # Halation analog: even-harmonic enrichment (tube/transformer bloom).
    # x|x| adds 2nd+3rd order harmonics without DC offset.
    "aeval=exprs='val(0)+0.07*val(0)*abs(val(0))|val(1)+0.07*val(1)*abs(val(1))'"
  when "spectral_warmth"
    # Color temperature analog: low-shelf boost + high-shelf cut.
    db = stock[:warmth_db].round(1)
    cut = (db * 0.65).round(1)
    "equalizer=f=90:width_type=o:width=2:g=#{db},equalizer=f=9500:width_type=o:width=2:g=-#{cut}"
  when "parallel_compress"
    # Bleach bypass analog: New York parallel compression.
    "acompressor=threshold=-22dB:ratio=7:attack=6:release=55:makeup=3:mix=0.45"
  when "multiband_tone"
    # Split grade analog: three-band independent tonal shaping.
    "equalizer=f=110:width_type=o:width=2:g=1.8,equalizer=f=900:width_type=o:width=2:g=0.5,equalizer=f=7000:width_type=o:width=2:g=-1.2"
  when "wow_flutter"
    # Reciprocity failure analog: capstan speed LFO (wow=slow, flutter=fast).
    r = stock[:wow_rate]
    d = stock[:wow_depth]
    "vibrato=f=#{r}:d=#{d}"
  when "vinyl_crackle"
    # Faded print analog: stochastic crackle bursts at ~0.08% of samples.
    "aeval=exprs='val(0)+if(lt(random(0),0.0008),(random(1)-0.5)*0.22,0)|" \
    "val(1)+if(lt(random(2),0.0008),(random(3)-0.5)*0.22,0)'"
  when "transient_sharpen"
    # Micro-contrast analog: presence boost via high-mid shelf.
    "equalizer=f=4000:width_type=o:width=1.5:g=2.0"
  when "stereo_width"
    # Chromatic aberration analog: M/S stereo widening.
    "extrastereo=m=1.35"
  when "print_through_echo"
    # Print-through analog: adjacent tape-layer bleed. True print-through is a
    # pre-echo; ffmpeg's aecho is forward-only, so this renders it as a faint
    # post-echo shadow of the same magnitude and timing (~40ms, -25dB).
    "aecho=1.0:0.056:38:0.11"
  when "reel_splice_clicks"
    # Reel splice analog: a physical tape join clicks once per reel length.
    "aeval=exprs='val(0)+if(lt(mod(t,42.5),0.0015),0.4*(random(0)-0.5),0)|" \
    "val(1)+if(lt(mod(t,42.5),0.0015),0.4*(random(1)-0.5),0)'"
  when "stylus_mistrack"
    # Groove mistracking analog: extra clipping kicks in only above a peak threshold.
    "aeval=exprs='val(0)+0.5*(tanh(4*val(0))-val(0))*gt(abs(val(0)),0.55)|" \
    "val(1)+0.5*(tanh(4*val(1))-val(1))*gt(abs(val(1)),0.55)'"
  when "platter_wow"
    # Off-centre pressing analog: wow locked to platter speed (33 1/3rpm ≈ 0.556Hz),
    # not tape capstan speed — slower and more periodic than wow_flutter.
    "vibrato=f=0.556:d=0.012"
  when "needle_drop_fade"
    # Needle-drop analog: stylus settling into a spinning groove.
    "afade=t=in:st=0:d=0.12:curve=qsin"
  when "haas_jitter"
    # Console crosstalk / Haas analog: asymmetric micro-delay per channel for width.
    "adelay=9|13,aecho=0.15:0.2:130:0.18"
  when "spring_reverb"
    # Spring tank analog: sparse, dispersive taps with a metallic mid resonance.
    "aecho=0.8:0.65:29|61|101|149:0.5|0.4|0.3|0.22,equalizer=f=2200:t=o:w=1.4:g=3.0,highpass=f=350"
  when "plate_reverb"
    # Plate analog: dense, closely spaced early reflections, smooth decay.
    "aecho=0.85:0.7:15|33|52|74|97|123:0.42|0.36|0.3|0.24|0.18|0.12"
  when "chamber_reverb"
    # Chamber analog: a few distinct early reflections before a short room tail.
    "aecho=0.9:0.6:41|83|127|179:0.38|0.30|0.22|0.15"
  when "dub_delay"
    # Dub delay analog: regenerating tape-echo feedback with saturation in the loop.
    "aecho=0.8:0.75:340|680:0.45|0.28,aeval=exprs='tanh(1.6*val(0))/#{Math.tanh(1.6).round(6)}|" \
    "tanh(1.6*val(1))/#{Math.tanh(1.6).round(6)}'"
  end
end

def sonitex_resolve_preset(track: nil)
  track ||= (ENV["TRACK"] || ENV["PROGRESSION"] || "chromatic_minor_descent").to_s.downcase.tr("-", "_")
  # SONITEX is the documented shorthand and SONITEX_PRESET the internal key
  # the style tables write. Reading the internal one first meant a caller's
  # SONITEX=heavy lost to whichever preset the style had just forced, so the
  # shorthand did nothing whenever a style was active -- which is always.
  # Whichever key the caller actually pinned wins; otherwise keep the old
  # order.
  raw = if USER_PINNED_ENV.key?("SONITEX") && !USER_PINNED_ENV.key?("SONITEX_PRESET")
          ENV["SONITEX"]
        else
          ENV["SONITEX_PRESET"] || ENV["SONITEX"]
        end.to_s.strip.downcase
  if raw.empty?
    # Was :donuts_warm — that preset's hf_rolloff/groove_wear_lp sit at
    # 2200/2600Hz (see its "not a 2 kHz blanket" sibling comment above
    # donuts_soul) and its out_comp_ratio is a full point hotter, burying
    # presence/air and sitting crest factor right at the reject-gate floor.
    # DILLA_STYLE_DEFAULTS/DILLA_BEST_DEFAULTS both already target
    # donuts_soul; this fallback had drifted out of sync with them.
    return :donuts_soul
  end
  return if raw =~ /\A(?:0|false|off)\z/
  return :heavy if %w[1 true on heavy].include?(raw)
  return :classic if %w[classic st1260 1260].include?(raw)
  return :extreme if %w[extreme st1269 1269].include?(raw)
  key = raw.to_sym
  SONITEX_PRESETS.key?(key) ? key : :heavy
end

def analog_chain_lookup(variant)
  key = variant.to_sym
  return ANALOG_CHAIN_VARIANTS[key] if ANALOG_CHAIN_VARIANTS.key?(key)
  return ANALOG_CHAIN_WILD[key] if ANALOG_CHAIN_WILD.key?(key)
  if @stream_wild_analog_chain && @stream_wild_analog_chain[:name] == key
    return { stock: @stream_wild_analog_chain[:stock], fx: @stream_wild_analog_chain[:fx] }
  end
  nil
end

def build_random_wild_analog_chain!(rng)
  stock = ANALOG_WILD_STOCKS.sample(random: rng)
  fx = GRADE_FX_POOL.shuffle(random: rng).first(rng.rand(5..8)).uniq
  unless fx.any? { |f| f.include?("warmth") || f.include?("saturation") }
    fx.unshift("spectral_warmth")
  end
  unless fx.any? { |f| f.include?("noise") || f.include?("crackle") }
    fx << "analog_noise"
  end
  name = :"wild_#{(@stream_iterate_count || 0)}_#{rng.rand(1000..9999)}"
  @stream_wild_analog_chain = { name:, stock:, fx: fx.uniq }
  name
end

def analog_resolve_variant(track: nil, rotate_index: nil)
  explicit = ENV["ANALOG_CHAIN"]&.strip
  if explicit && !explicit.empty? && explicit != "auto"
    key = explicit.to_sym
    return key if analog_chain_lookup(key)
    return build_random_wild_analog_chain!(render_rng("wild_analog_chain")) if %w[wild wild_random random].include?(explicit)
  end
  idx = rotate_index
  unless idx
    t = track || ENV["TRACK"]
    idx = TAPE_RENDER_CATALOG.index { |e| e[:preset].to_s == t.to_s } if t
    idx ||= 0
  end
  pool = ANALOG_CHAIN_ROTATE + ANALOG_CHAIN_WILD_ROTATE
  pool[idx % pool.length]
end

def analog_emulation_filters(input_tag, variant, out_tag: "ana_out")
  cfg = analog_chain_lookup(variant) || ANALOG_CHAIN_VARIANTS.fetch(variant)
  stock = AUDIO_STOCKS[cfg[:stock]]
  parts = cfg[:fx].map { |fx| grade_filter(fx, stock) }.compact
  return ["[#{input_tag}]anull[#{out_tag}]"] if parts.empty?
  segs = []
  tag = input_tag
  parts.each_with_index do |filt, i|
    nxt = "ana#{i}"
    segs << "[#{tag}]#{filt}[#{nxt}]"
    tag = nxt
  end
  segs << "[#{tag}]lowpass=f=#{stock[:rolloff_hz]}[#{out_tag}]"
  segs
end

def analog_list
  puts "Analog chain variants (ANALOG_CHAIN= or auto-rotate per session):"
  ANALOG_CHAIN_VARIANTS.each do |name, cfg|
    puts "  #{name}: #{cfg[:fx].join(' → ')} [#{cfg[:stock]}]"
  end
  puts "Wild mashups (stream auto-iterate + ANALOG_CHAIN=wild):"
  ANALOG_CHAIN_WILD.each do |name, cfg|
    puts "  #{name}: #{cfg[:fx].join(' → ')} [#{cfg[:stock]}]"
  end
end

# Off wherever a sampled bed is playing.
#
# Sonitex here is our emulation of the Sonitex STX-1260, a Danish plugin that
# models the whole path of a sampler-era record -- and it sits on the MASTER
# bus, so it does not process the drums and leave the record alone. It processes
# everything, the record included. On donuts_warm that means twelve-bit crushing
# at 42 percent wet, a tanh waveshaper at 62 percent wet, and a rolloff from
# 7 kHz, applied to a sample that was already a broadcast recording of a record.
#
# That is one generation of ageing too many, and the wrong direction for this
# material. The chops arrive with their own age already on them. What they want
# is the other half of the Cooley principle -- make old things sound new -- which
# is what sample_modern_chain below was written to do: definition, extension,
# and the room the broadcast lost, rather than more wear.
#
# The gate is live and removes Sonitex from every sample-backed render.
# sample_modern_chain runs on the loop bus (build_sample_loop_filter) unless
# SAMPLE_MODERN=0, so the bed gets the addition that matches the subtraction.
#
# Synthesised material is the opposite case. It has no age of its own, and
# giving it some is exactly what the emulation is for, so nothing changes there.
#
# SONITEX= set explicitly still wins, so it can be forced back on per render.
# USER_PINNED_ENV, not ENV -- the same distinction the BPM code makes, and for
# the same reason. DILLA_STYLE_DEFAULTS writes ENV["SONITEX"] itself, so asking
# ENV whether anyone set it always answers yes, and the escape hatch defeats the
# gate it is attached to. The first version of this gate read ENV and did
# nothing at all.
def sonitex_enabled?
  pinned = USER_PINNED_ENV["SONITEX"].to_s.strip
  return false if sample_backed_render? && pinned.empty?

  !sonitex_resolve_preset.nil?
end

# Is a sampled loop actually playing on this render?
def sample_backed_render?
  return false if ENV["SAMPLE_LOOP"].to_s == "0"

  !sample_loop_for(ENV["TRACK"]).nil?
end

# Makes the old record sound new.
#
# The other direction from every other treatment in this engine, and the harder
# half of what Dave Cooley described: old things new, new things old. Everything
# here restores something the source lost rather than adding something it never
# had.
#
# A chop off an off-air broadcast has four specific problems, and one stage each:
#
#   HISS. Broadcast noise floor and mp3 artefacts. A spectral denoiser removes
#   what is constant across the whole file, which is exactly what a noise floor
#   is, while leaving the music that changes.
#
#   NO TOP. Broadcast bandwidth and a lossy codec both stop well short of 20 kHz,
#   so there is nothing above about 15. It cannot be equalised back --
#   boosting silence gives louder silence. It has to be SYNTHESISED, by generating
#   harmonics from the content just below the cliff. This is what aexciter is
#   for, and its refusal to touch anything below its frequency -- which made it
#   useless as a broadband saturator earlier -- is precisely the behaviour wanted
#   here.
#
#   NO SUB. Same story at the bottom, and the same answer: asubboost generates
#   a fundamental beneath what is there.
#
#   NO DEPTH. A broadcast is squashed to near-mono by its own processing.
#   Widening the sides restores space without touching the centre, where the
#   melody is.
def sample_modern_chain
  return nil if ENV["SAMPLE_MODERN"] == "0"

  [
    "afftdn=nf=#{ENV.fetch('SAMPLE_DENOISE_DB', '-28')}:tn=1",
    "adeclick",
    "aexciter=amount=#{ENV.fetch('SAMPLE_AIR', '1.4')}:drive=6:blend=2:freq=8500:level_out=1",
    "asubboost=dry=1:wet=#{ENV.fetch('SAMPLE_SUB', '0.35')}:decay=0.6:feedback=0.7:cutoff=110",
    "stereowiden=delay=18:feedback=0.28:crossfeed=0.25:drymix=0.85",
  ].join(",")
end

# STX-1260 sections. The DeviceChain is already this shape; the preset table
# was one flat hash, so `subtle` turned crush, hiss, drive and wow down
# together and "vinyl tone without the bit-crush" was inexpressible.
SONITEX_SECTIONS = {
  mix: %i[comp_threshold comp_ratio comp_attack comp_release comp_makeup stereo_width side_gain
          out_comp_threshold out_comp_ratio out_comp_makeup limit level_out],
  distortion: %i[dist_pre_emph_db dist_pre_lp dist_drive dist_mix dist_dc],
  vinyl: %i[hf_rolloff lf_rolloff head_bump_hz head_bump_db groove_wear_lp wow_rate wow_depth flutter_hz flutter_depth],
  tone: %i[warmth_db sibilance_db sibilance_hz phone_lp],
  noise: %i[hiss_amp pop_rate pop_amp click_rate],
  sampling: %i[crush_bits crush_sr crush_mix crush_post_lp],
}.freeze

# Fully dry values for a section amount of 0. Amount 1 is the preset (no-op).
SONITEX_SECTION_BYPASS = {
  stereo_width: 1.0, side_gain: 1.0,
  comp_ratio: 1.0, comp_makeup: 0.0, out_comp_ratio: 1.0, out_comp_makeup: 0.0,
  limit: 1.0, level_out: 1.0,
  dist_mix: 0.0, dist_drive: 1.0, dist_dc: 0.0, dist_pre_emph_db: 0.0,
  head_bump_db: 0.0, hf_rolloff: 20_000, groove_wear_lp: 20_000, lf_rolloff: 20,
  wow_depth: 0.0, flutter_depth: 0.0,
  warmth_db: 0.0, sibilance_db: 0.0, phone_lp: 20_000,
  hiss_amp: 0.0, pop_rate: 0.0, click_rate: 0.0, pop_amp: 0.0,
  crush_mix: 0.0, crush_bits: 16, crush_sr: 1.0, crush_post_lp: 20_000,
}.freeze

def sonitex_section_amount(name)
  raw = ENV["SONITEX_#{name.to_s.upcase}"].to_s.strip
  return 1.0 if raw.empty?
  return 0.0 if raw.match?(/\A(?:0|false|off)\z/i)
  return 1.0 if raw.match?(/\A(?:1|true|on)\z/i)

  raw.to_f.clamp(0.0, 1.0)
end

def sonitex_apply_sections(cfg)
  out = cfg.dup
  SONITEX_SECTIONS.each do |section, keys|
    amount = sonitex_section_amount(section)
    next if amount >= 1.0

    keys.each do |key|
      next unless out.key?(key)

      bypass = SONITEX_SECTION_BYPASS[key]
      next if bypass.nil?

      mixed = (out[key] * amount) + (bypass * (1.0 - amount))
      out[key] = cfg[key].is_a?(Integer) ? mixed.round : mixed
    end
  end
  out
end

def sonitex_config(track: nil)
  sonitex_apply_sections(SONITEX_PRESETS.fetch(sonitex_resolve_preset(track:) || :classic))
end

# Report what the master bus actually did, not what the preset table resolves to.
#
# This asked sonitex_resolve_preset directly while master_bus_filters_enhanced
# gates on sonitex_enabled?, so every sample-backed render printed "Sonitex
# STX-1260 (donuts_warm)" in its summary while taking the dry branch and
# applying none of it. The rule that keeps the emulation off old records was
# working; the only way to check it said the opposite.
def sonitex_label
  return "dry" unless sonitex_enabled?

  preset = sonitex_resolve_preset
  return "dry" unless preset
  variant = analog_resolve_variant
  "Sonitex STX-1260 (#{preset}) + analog:#{variant}"
end

def sonitex_list
  puts "Sonitex STX-1260 presets (SONITEX_PRESET= or SONITEX=):"
  SONITEX_PRESETS.each_key do |name|
    mark = name == (sonitex_resolve_preset || :classic) ? " *" : ""
    puts "  #{name}#{mark}"
  end
end

# ST-1260 life-span chain — ends at snx_out; limiter applied in master_bus_filters.
def sonitex_tape_filters(input_tag = "mix", out_tag: "snx_out")
  unless sonitex_enabled?
    return ["[#{input_tag}]alimiter=limit=0.90:level_out=0.92[out]"]
  end
  s = sonitex_config
  d = s[:dist_drive]
  n = Math.tanh(d).round(6)
  dry_w = (1.0 - s[:dist_mix]).round(3)
  wet_w = s[:dist_mix].round(3)
  pop_dyn = s[:pop_amp].round(3)
  # Each Device is one self-contained labeled ffmpeg segment (input/output
  # tags already embedded) -- .to_a below is byte-identical to the plain
  # array literal this replaced, introspectable (`ruby dilla.rb tracks`).
  chain = DillaMixer::DeviceChain.new([
    DillaMixer::Device.new(:comp,
      "[#{input_tag}]acompressor=threshold=#{s[:comp_threshold]}dB:ratio=#{s[:comp_ratio]}:attack=#{s[:comp_attack]}:release=#{s[:comp_release]}:makeup=#{s[:comp_makeup]}[snx1]"),
    DillaMixer::Device.new(:stereo_width, "[snx1]extrastereo=m=#{s[:stereo_width]}[snx2]"),
    DillaMixer::Device.new(:split_dry_wet, "[snx2]asplit=2[snx_dry][snx_wet]"),
    DillaMixer::Device.new(:pre_emphasis,
      "[snx_wet]equalizer=f=2800:t=o:w=1.2:g=#{s[:dist_pre_emph_db]},lowpass=f=#{s[:dist_pre_lp]}[snx_pre]"),
    DillaMixer::Device.new(:saturate,
      "[snx_pre]aeval=exprs='tanh(#{d}*(val(0)+#{s[:dist_dc]}))/#{n}|tanh(#{d}*(val(1)+#{s[:dist_dc]}))/#{n}'[snx_sat]"),
    DillaMixer::Device.new(:de_emphasis, "[snx_sat]equalizer=f=2800:t=o:w=1.2:g=#{-s[:dist_pre_emph_db]}[snx_de]"),
    DillaMixer::Device.new(:dry_wet_mix, "[snx_dry][snx_de]amix=inputs=2:weights=#{dry_w} #{wet_w}:duration=longest[snx3]"),
    DillaMixer::Device.new(:tone_shape,
      "[snx3]highpass=f=#{s[:lf_rolloff]}:width_type=q:width=0.9," \
      "equalizer=f=#{s[:head_bump_hz]}:t=o:w=0.82:g=#{s[:head_bump_db]}," \
      "equalizer=f=82:t=o:w=2:g=#{s[:warmth_db]}," \
      "lowpass=f=#{s[:hf_rolloff]}:width_type=q:width=0.85," \
      "lowpass=f=#{s[:groove_wear_lp]}[snx4]"),
    DillaMixer::Device.new(:wow, "[snx4]vibrato=f=#{s[:wow_rate]}:d=#{s[:wow_depth]}[snx5]"),
    DillaMixer::Device.new(:flutter, "[snx5]vibrato=f=#{s[:flutter_hz]}:d=#{s[:flutter_depth]}[snx6]"),
    DillaMixer::Device.new(:phone_sibilance,
      "[snx6]lowpass=f=#{s[:phone_lp]},equalizer=f=#{s[:sibilance_hz]}:t=o:w=1.1:g=#{s[:sibilance_db]}[snx7]"),
    DillaMixer::Device.new(:hiss,
      "[snx7]aeval=exprs='(val(0)+#{s[:hiss_amp]}*(random(0)-0.5))|" \
      "(val(1)+#{s[:hiss_amp]}*(random(1)-0.5))'[snx8]"),
    DillaMixer::Device.new(:pops_clicks,
      "[snx8]aeval=exprs='val(0)+if(lt(random(2),#{s[:pop_rate]}),(random(3)-0.5)*#{pop_dyn}*max(0.15,1-1.8*abs(val(0))),0)|" \
      "val(1)+if(lt(random(4),#{s[:click_rate]}),(random(5)-0.5)*#{(pop_dyn * 0.55).round(3)}*max(0.15,1-1.8*abs(val(1))),0)'[snx9]"),
    DillaMixer::Device.new(:crush, "[snx9]acrusher=bits=#{s[:crush_bits]}:samples=#{s[:crush_sr]}:mix=#{s[:crush_mix]}[snx10]"),
    DillaMixer::Device.new(:crush_post_lp, "[snx10]lowpass=f=#{s[:crush_post_lp]}[snx11]"),
    DillaMixer::Device.new(:exciter, "[snx11]aeval=exprs='#{HEDD}'[snx12]"),
    DillaMixer::Device.new(:output_comp,
      "[snx12]acompressor=threshold=#{s[:out_comp_threshold]}dB:ratio=#{s[:out_comp_ratio]}:attack=22:release=120:makeup=#{s[:out_comp_makeup]}[#{out_tag}]"),
  ])
  @last_sonitex_device_chain = chain
  chain.to_a
end

# Dilla drum bus — NY parallel compression, sub bump, mix low-pass from measured centroid (~1061 Hz).
def dilla_mix_preprocess_filters(input_tag = "mix", out_tag: "dpre")
  [
    "[#{input_tag}]asplit=2[dm_dry][dm_par]",
    "[dm_par]acompressor=threshold=-30dB:ratio=4.5:attack=2:release=48:makeup=3.0[dm_pc]",
    "[dm_dry][dm_pc]amix=inputs=2:weights=0.80 0.20:duration=first[dm_ny]",
    "[dm_ny]extrastereo=m=1.14[dm_wide]",
    "[dm_wide]equalizer=f=58:t=o:w=0.7:g=5.2,equalizer=f=92:t=o:w=1.2:g=3.6," \
    "equalizer=f=2200:t=o:w=1.4:g=-3.2,lowpass=f=2400[#{out_tag}]",
  ]
end

# Sonitex + creative analog grade stack + streaming loudness delivery.
# loudnorm supplies EBU R128 integrated loudness and true-peak analysis (including
# its oversampled peak path); the final limiter remains a deterministic last guard.
MASTER_TARGET_LUFS = -17.0
TRUE_PEAK_CEILING_DB = -1.0
# Encoder headroom. alimiter caps SAMPLE peak; the delivery spec is TRUE peak,
# and lame reconstructs inter-sample peaks above whatever ceiling the samples
# were held to. Limiting at exactly -1.0 therefore ships a file measuring above
# -1.0: eleven of thirty-four renders in renders/beats sit at or above it and
# one at +0.1 dBFS, each with "true peak exceeds -1 dBTP" recorded in its own
# quality sidecar. Measured on this tree 2026-08-13, 0.6 dB is the allowance
# that puts an encoded master back under the ceiling it declares.
TRUE_PEAK_ENCODER_HEADROOM_DB = 0.6
TRUE_PEAK_CEILING_LINEAR = (10**((TRUE_PEAK_CEILING_DB - TRUE_PEAK_ENCODER_HEADROOM_DB) / 20.0)).round(4)

# Every Sonitex preset's own warmth/head-bump EQ re-boosts the sub-100Hz band
# the sample bass and synth bass already occupy, earlier in the chain — undoing
# any balance correction placed before it. This is the one point both the dry
# and Sonitex paths funnel through right before the final safety limiter, so
# it's the only place a correction here actually sticks.
#
# This paragraph named a second cause until 2026-08-12: dilla_mix_preprocess_
# filters' NY drum bump, +5.2dB@58Hz and +3.6dB@92Hz. That method has no caller
# and never had one, so half of what these numbers were set against was never
# in the signal path. The numbers are left exactly as they are — they were tuned
# by ear against what the master actually sounded like, not derived from this
# comment, so the comment was wrong and the cut may still be right. But if the
# non-flylo -11dB@95Hz ever sounds like too much bass removed, this is why.
def mix_bass_chord_balance_filter(input_tag, out_tag: "balanced")
  # Sonitex warmth re-boosts sub; this stage tames sustained bass so chords
  # stay clear. On Camel/FlyLo the same -11dB@95Hz was also deleting kick
  # fundamentals — protect the 45–70Hz pocket when the kit is primary.
  if flylo_primary_drums?
    cut = sonitex_enabled? ? -5.5 : -3.5
    boost = sonitex_enabled? ? 5.5 : 4.5
    kick_restore = 4.2
  else
    cut = sonitex_enabled? ? -11.0 : -7.0
    boost = sonitex_enabled? ? 8.0 : 6.0
    kick_restore = deep_render? ? 2.4 : 1.6
    cut -= 1.5 if deep_render?
    boost += 1.2 if deep_render?
  end
  "[#{input_tag}]bass=g=#{cut}:f=95:width_type=h:w=170,equalizer=f=300:t=h:w=360:g=#{boost}," \
    "equalizer=f=55:t=o:w=0.75:g=#{kick_restore}[#{out_tag}]"
end

# Real mix-engineering technique: sum everything below ~120Hz to mono.
# Stereo-widened sub content cancels on real speakers/systems (especially
# mono or near-mono playback) and phase-cancellation down there is where
# translation problems actually come from — the highs can stay wide.
def sub_bass_mono_filter(input_tag, out_tag: "monobassed")
  "[#{input_tag}]asplit=2[sblo_src][sbhi_src];" \
  "[sblo_src]lowpass=f=120,pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1[sblo];" \
  "[sbhi_src]highpass=f=120[sbhi];" \
  "[sblo][sbhi]amix=inputs=2:weights=1.0 1.0:duration=first:normalize=0[#{out_tag}]"
end

# Very slow, subtle continuous pitch/tempo drift — real tape/vinyl
# never holds perfectly still. Two independent slow LFOs (not locked to
# the same rate) so it doesn't read as a single obvious wobble.
def analog_drift_filter(input_tag, out_tag: "drifted")
  "[#{input_tag}]vibrato=f=0.13:d=0.0035,vibrato=f=0.19:d=0.002[#{out_tag}]"
end

CONVOLUTION_IR_CACHE = File.join(SCRATCH_DIR, "ir_%s.wav")

# Real convolution reverb via ffmpeg's afir filter — genuinely convolving
# against an impulse response, a synthesized one (exponentially
# decaying filtered noise per "room") rather than a recorded one, since no
# real IR files exist in this repo. That's a legitimate, standard way to
# build a reverb IR algorithmically, not a fake stand-in for the effect.
CONVOLUTION_ROOMS = {
  plate: { decay: 2.6, color: "highpass=f=400,lowpass=f=6000" },
  room: { decay: 1.1, color: "highpass=f=120,lowpass=f=4500" },
  chamber: { decay: 3.4, color: "highpass=f=200,lowpass=f=3200" },
}.freeze

def synth_impulse_response!(room)
  path = format(CONVOLUTION_IR_CACHE, room)
  return path if File.exist?(path)
  FileUtils.mkdir_p(SCRATCH_DIR)
  cfg = CONVOLUTION_ROOMS.fetch(room)
  decay_rate = (3.0 / cfg[:decay]).round(3)
  sh! "ffmpeg", "-y", "-f", "lavfi", "-i", "anoisesrc=color=white:d=#{cfg[:decay] + 0.3}:r=#{SAMPLE_RATE}:seed=#{noise_seed(1)}",
      "-af", "aeval=exprs='val(0)*exp(-#{decay_rate}*t)|val(1)*exp(-#{decay_rate}*t)',#{cfg[:color]}",
      "-ac", "2", "-ar", SAMPLE_RATE.to_s, path
  path
end

# Real convolution against the synthesized IR (via ffmpeg's afir filter),
# ir_input_idx being the ffmpeg -i index the caller has already added —
# same pattern as the self-sample bus: this function only builds the
# filter-graph string, the caller owns adding the actual -i input.
def convolution_reverb_filter(input_tag, ir_input_idx, mix: 0.16, out_tag: "convolved")
  "[#{input_tag}]asplit=2[#{out_tag}dry][#{out_tag}wetsrc];" \
    "[#{out_tag}wetsrc][#{ir_input_idx}:a]afir=dry=0:wet=10[#{out_tag}wet];" \
    "[#{out_tag}dry][#{out_tag}wet]amix=inputs=2:weights=#{(1.0 - mix).round(2)} #{mix}:duration=first:normalize=0[#{out_tag}]"
end

# Darker/deeper tonal color: gentle high rolloff (less brightness/major
# "shimmer") plus a bit more low-mid weight — moodier without changing any
# chord quality, on top of the STREAM_TRACKS rotation now leaning minor.
def analog_smooth_enabled?
  ENV.fetch("ANALOG_SMOOTH", "1") != "0"
end

# Round off the two extremes the way a tape machine and a transformer do, rather
# than the way a filter does.
#
# The chain already had a brick lowpass in mood_darken_filter and a limiter at
# the end, which is not the same thing: a lowpass removes the top instead of
# softening it, and a limiter flattens peaks without touching what makes them
# harsh. What was left over at both ends is what a mix engineer takes out by
# hand -- subsonic rumble under the kick that eats headroom and makes the low end
# read as flab rather than weight, and the 3 kHz shelf where a synthesised lead
# and a sampled hat both live, which is where "digital" is actually heard.
#
# So, from the bottom up: a two-pole highpass at 30 Hz for the rumble, a narrow
# cut at 85 Hz for the boom, a wide dip at 3.2 kHz for the harshness, a de-esser
# for what is harsh only sometimes, then tanh soft clipping -- the analog part,
# which rounds transients at both ends and adds the low-order harmonics that make
# the result read as warm instead of merely darker -- and a gentle air shelf last,
# so it also shapes the harmonics the clipper just generated.
#
# ANALOG_SMOOTH=0 turns it off; ANALOG_SMOOTH_STRENGTH scales every move.
def analog_smooth_filter(input_tag, out_tag: "smoothed", strength: nil)
  s = (strength || ENV.fetch("ANALOG_SMOOTH_STRENGTH", "1.0").to_f).clamp(0.0, 2.0)
  boom = (-1.6 * s).round(1)
  harsh = (-1.5 * s).round(1)
  air = (-2.0 * s).round(1)
  # Drive into the clipper and back out, rather than lowering its threshold.
  #
  # asoftclip's threshold is absolute, and this stage runs before loudnorm, so a
  # fixed threshold rounds a hot mix and does nothing at all to a quiet one.
  # Pre-gain fixes the relationship: only peaks within `drive` dB of full scale
  # get rounded, whatever the mix level, which is the level-dependent behaviour
  # the analog stage is imitating in the first place.
  #
  # oversample stays at 1. Measured on this ffmpeg (8.1.1), oversample=2 costs
  # 5.8 dB of level with no gain compensation and generates no harmonics, so it
  # was pure attenuation that loudnorm would have handed straight back.
  drive = (3.0 * s).round(1)
  "[#{input_tag}]highpass=f=30:p=2," \
    "equalizer=f=85:t=q:w=1.0:g=#{boom}," \
    "equalizer=f=3200:t=q:w=1.2:g=#{harsh}," \
    "deesser=i=#{(0.18 * s).round(2)}:m=0.4:f=0.55:s=o," \
    "volume=#{drive}dB,asoftclip=type=tanh:threshold=1:output=1:oversample=1,volume=-#{drive}dB," \
    "equalizer=f=8000:t=h:w=4000:g=#{air}[#{out_tag}]"
end

def mood_darken_filter(input_tag, out_tag: "darkened", strength: 1.0)
  hi_cut = (-3.5 * strength).round(1)
  low_boost = (2.0 * strength).round(1)
  ceiling = strength < 0.7 ? 12_500 : 11_000
  "[#{input_tag}]equalizer=f=5500:t=h:w=4000:g=#{hi_cut},equalizer=f=220:t=h:w=180:g=#{low_boost},lowpass=f=#{ceiling}[#{out_tag}]"
end

# A real destabilizing moment, not another polite EQ nudge: heavy
# lowpass+bitcrush gate right before the build lands, then a short hard
# silence gap — the mix actually breaks for a beat instead of getting
# brighter. Fires at 79% through, build_up_filter picks up right after.
def break_filter(input_tag, duration, out_tag: "broke")
  break_t = (duration * 0.79).round(2)
  gate_dur = 0.6
  silence_dur = 0.18
  "[#{input_tag}]" \
    "lowpass=f=600:enable='between(t,#{break_t},#{break_t + gate_dur})'," \
    "acrusher=bits=6:samples=8:mix=0.8:enable='between(t,#{break_t},#{break_t + gate_dur})'," \
    "volume=0:enable='between(t,#{break_t + gate_dur},#{break_t + gate_dur + silence_dur})'" \
    "[#{out_tag}]"
end

def master_bus_filters(input_tag = "mix", track: nil, duration: nil, ir_input_idx: nil, cfg: nil)
  cfg ||= dilla_resolve_config
  filt = master_bus_filters_enhanced(input_tag, cfg:, duration:, ir_input_idx:)
  return filt unless DillaMaster.enabled?

  guard = filt.pop
  pre = guard[/\A\[(\w+)\]/, 1] || "built"
  mh = DillaMaster.extra_filters(pre, cfg:, duration:)
  filt.concat(mh) if mh.any?
  inlet = mh.any? ? "#{pre}_mh" : pre
  filt << guard.sub("[#{pre}]", "[#{inlet}]")
  filt
end

def grade(input = nil, output = nil, preset_name = nil)
  input       ||= prompt("audio path")
  preset_name ||= prompt("preset (#{GRADE_PRESETS.keys.join(', ')})")
  output      ||= input.sub(/(\.\w+)\z/, "_#{preset_name}\\1")
  abort "missing #{input}" unless File.exist?(input)
  p = GRADE_PRESETS[preset_name.to_sym] or abort "unknown preset: #{preset_name}. valid: #{GRADE_PRESETS.keys.join(', ')}"
  stock = AUDIO_STOCKS[p[:stock]]
  filters = p[:fx].map { |fx| grade_filter(fx, stock) }.compact
  abort "no filters for preset #{preset_name}" if filters.empty?
  chain = [filters, "lowpass=f=#{stock[:rolloff_hz]}"].flatten.join(",")
  sh! "ffmpeg", "-y", "-i", input, "-af", chain, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
end

def grade_list
  GRADE_PRESETS.each do |name, p|
    stock = p[:stock]
    puts "#{name}: #{p[:fx].join(' → ')} [#{stock}]"
  end
end
