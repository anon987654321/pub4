# frozen_string_literal: true

# How much of a look's intensity each effect gets. A preset or a recipe step
# names one intensity for the whole look; each effect is mixed down from it by
# its own factor here, calibrated per effect, because a colourist runs a look
# below full strength and some effects (a bloom, a bleach) read at a quarter of
# the strength others need. Effects not listed take the intensity as it comes,
# or scale it in their own arm of grade_step where the source also has a say.
EFFECT_MIX = {
  "adaptive_contrast" => 0.70,
  "adjacency_effects" => 0.25,
  "aerial_depth" => 0.45,
  "anamorphic_flare" => 0.50,
  "bleach_bypass" => 0.40,
  "bloom_pro" => 0.25,
  "bokeh_rendering" => 0.35,
  "clarity" => 0.65,
  "color_separate" => 0.55,
  "color_temp" => 0.50,
  "cross_fade" => 0.40,
  "crt_phosphor_bloom" => 0.50,
  "crt_scanlines" => 0.35,
  "darkroom_print" => 0.50,
  "day_for_night" => 0.70,
  "desaturate" => 0.45,
  # A band-pass lift of 2.8x its intensity: at full look strength it embossed
  # the frame. This lands it beside clarity, about a third of the band at most.
  "dilla_head_bump" => 0.12,
  "dir_coupler" => 0.12,
  "dodgeburn_artifacts" => 0.40,
  "dust_and_hair" => 0.50,
  "edge_aware_nr" => 0.55,
  "film_shoulder" => 0.75,
  "fixing_bath_fog" => 0.30,
  "gate_weave" => 0.40,
  "green_push" => 0.15,
  "halation" => 0.60,
  "hi8_chroma_noise" => 0.40,
  "highlight_roll" => 0.50,
  "infrared" => 0.85,
  "kodachrome_sim" => 0.75,
  "lens_ghosting" => 0.35,
  "light_leaks" => 0.45,
  "lith_print" => 0.75,
  "longitudinal_ca" => 0.50,
  "micro_contrast" => 0.20,
  "minidv_block_dropout" => 0.35,
  "newton_rings" => 0.12,
  "orange_mask" => 0.90,
  "ortho_film" => 0.80,
  "paper_texture" => 0.35,
  "print_film" => 0.70,
  "relight" => 0.55,
  "reticulation" => 0.50,
  "scan_noise" => 0.40,
  "selective_sharpen" => 0.65,
  "selenium_tone" => 0.45,
  "spectral_temp" => 0.50,
  "split_grade" => 0.25,
  "stock_matrix" => 0.85,
  "teal_orange" => 0.80,
  "technicolor" => 0.55,
  "tilt_shift" => 0.70,
  "tonemap" => 0.85,
  "vhs_chroma_delay" => 0.40,
  "vhs_head_switch_band" => 0.40,
  "vhs_interlace_comb" => 0.40,
  "vhs_luma_bleed" => 0.40,
  "vhs_tracking_noise" => 0.40,
  "vintage_lens" => 0.70,
  "warmth" => 0.25,
}.freeze

# One step of a grade, calibrated. Every effect is mixed down from the look's
# intensity by its own factor here, the subtractive ones are scaled by what the
# source arrived with (`head`), and the stock, print stock, stops and the rest
# come from `p`. preset() and recipe() both grade through this, so a random
# take built from a look is that look and not its effects at raw strength:
# measured 2026-10-27, the uncalibrated path ran bloom at four times and bleach
# at two and a half times the strength the presets give them, blurred sharp
# photographs the taper would have spared, and wrecked 69% of its takes.
def grade_step(fx, processed, p, head, owner = "chain")
  level = p[:intensity]
  mix = level * EFFECT_MIX.fetch(fx, 1.0)
  stock = p[:stock]
  case fx
  when "optical_blur"        then optical_blur(processed, 0.5 * head[:blur])
  when "tonemap"             then tonemap(processed, type: p.fetch(:tonemap, :aces2), exposure: p.fetch(:tonemap_ev, 0.0), intensity: mix)
  when "halation"            then halation(processed, mix, tint: halation_tint_for(stock))
  when "film_curve"          then film_curve(processed, stock, level * head[:curve])
  when "stock_matrix"        then stock_matrix(processed, stock, mix)
  when "spectral_temp"       then spectral_temp(processed, source_kelvin: 6504, target_kelvin: p[:temp], intensity: mix)
  when "color_temp"          then color_temp(processed, p[:temp], mix)
  when "dir_coupler"         then dir_coupler(processed, mix)
  when "push_pull"           then push_pull(processed, p.fetch(:stops, 1.0), stock)
  when "bleach_bypass"       then bleach_bypass(processed, mix)
  when "reciprocity_failure" then reciprocity_failure(processed, p.fetch(:exposure_secs, 10.0), stock)
  when "orange_mask"         then orange_mask(processed, stock, mix)
  when "print_film"          then print_film(processed, p.fetch(:print_stock, :kodak_2383), mix)
  when "split_grade"         then split_grade(processed, intensity: mix)
  when "split_toning"        then split_toning(processed)
  when "skin_protect"        then skin_protect(processed, level)
  when "shadow_lift"         then shadow_lift(processed, SHADOW_TOE_TARGET, true)
  when "light_leaks"         then light_leaks(processed, mix)
  when "day_for_night"       then day_for_night(processed, mix)
  when "highlight_roll"      then highlight_roll(processed, 200, mix)
  when "micro_contrast"      then micro_contrast(processed, 5, mix)
  # Was a hard-coded 800 for every preset. grain's whole ISO term is
  # sqrt(iso/100), so a constant made it a constant: Velvia 50 and
  # Delta 3200 were graining at the same speed and differed only by
  # their sigma. Now each stock states its own box speed, and a push
  # raises the effective one, which is what pushing IS -- rating the
  # film faster than it is and paying for it in grain. Safe to change
  # today of all days: grain raised on every call until this session,
  # so no render anywhere has a grain pattern to preserve.
  when "grain"               then grain(processed, preset_effective_iso(p), stock, level)
  when "color_separate"      then color_separate(processed, mix)
  when "chromatic_aberration" then chromatic_aberration(processed, level * 0.25 * head[:fringe])
  when "vintage_lens"        then vintage_lens(processed, p.fetch(:lens, "zeiss"), mix)
  when "teal_orange"         then teal_orange(processed, mix)
  when "bloom_pro"           then bloom_pro(processed, mix)
  # The measured depth map rides along on both shape stages; a cache
  # miss costs about twelve seconds, which the chain spends in
  # glows anyway. nil degrades both to their own cues.
  when "relight"             then relight(processed, mix, azimuth: p.fetch(:azimuth, 135.0), shape: p.fetch(:shape, 1.25), depth: Postpro::Depth.near(processed))
  when "aerial_depth"        then aerial_depth(processed, mix, depth: Postpro::Depth.near(processed))
  when "desaturate"          then desaturate(processed, mix)
  when "warmth"              then warmth(processed, mix)
  when "green_push"          then green_push(processed, mix)
  when "cross_fade"          then cross_fade(processed, mix)
  when "infrared"            then infrared(processed, mix)
  when "lith_print"          then lith_print(processed, mix)
  when "kodachrome_sim"      then kodachrome_sim(processed, mix)
  when "technicolor"         then technicolor(processed, mix)
  when "cyanotype"           then cyanotype(processed, level)
  when "faded_print"         then faded_print(processed, p.fetch(:age, 0.40))
  when "base_tint"           then base_tint(processed, [255, 250, 242], 0.07)
  when "dual_base_density"   then dual_base_density(processed, [255, 248, 236], 0.06)
  when "emulsion_defocus"    then emulsion_defocus(processed, stock)
  when "adjacency_effects"   then adjacency_effects(processed, mix)
  when "longitudinal_ca"     then longitudinal_ca(processed, mix)
  when "lens_distortion"     then lens_distortion(processed, p.fetch(:k1, -0.12))
  when "bokeh_rendering"     then bokeh_rendering(processed, mix)
  when "anamorphic_flare"    then anamorphic_flare(processed, mix)
  when "diffraction_blur"    then diffraction_blur(processed, p.fetch(:f_number, 16.0))
  when "scan_noise"          then scan_noise(processed, mix)
  when "newton_rings"        then newton_rings(processed, mix)
  when "dust_and_hair"       then dust_and_hair(processed, mix)
  when "film_curl_vignette"  then film_curl_vignette(processed, level * 0.45 * head[:vignette])
  when "selenium_tone"       then selenium_tone(processed, mix)
  when "dye_fade"            then dye_fade(processed, stock, p.fetch(:age, 0.50))
  when "darkroom_print"      then darkroom_print(processed, mix)
  when "film_base_density"   then film_base_density(processed, stock, 0.06)
  when "paper_texture"       then paper_texture(processed, mix)
  when "dodgeburn_artifacts" then dodgeburn_artifacts(processed, mix)
  when "fixing_bath_fog"     then fixing_bath_fog(processed, mix)
  when "reticulation"        then reticulation(processed, mix)
  when "expired_film"        then expired_film(processed, p.fetch(:age, 0.60))
  when "gate_weave"          then gate_weave(processed, mix)
  when "lens_ghosting"       then lens_ghosting(processed, mix)
  when "ortho_film"          then ortho_film(processed, mix)
  when "tilt_shift"          then tilt_shift(processed, mix)
  when "adaptive_contrast"   then adaptive_contrast(processed, mix)
  when "film_shoulder"       then film_shoulder(processed, mix)
  when "clarity"             then clarity(processed, 15, mix)
  when "edge_aware_nr"       then edge_aware_nr(processed, mix)
  when "selective_sharpen"   then selective_sharpen(processed, mix)
  when "vhs_luma_bleed"      then vhs_luma_bleed(processed, mix)
  when "vhs_chroma_delay"    then vhs_chroma_delay(processed, mix)
  when "vhs_head_switch_band" then vhs_head_switch_band(processed, mix)
  when "vhs_tracking_noise"  then vhs_tracking_noise(processed, mix)
  when "vhs_interlace_comb"  then vhs_interlace_comb(processed, mix)
  when "crt_phosphor_bloom"  then crt_phosphor_bloom(processed, mix)
  when "crt_scanlines"       then crt_scanlines(processed, mix)
  when "minidv_block_dropout" then minidv_block_dropout(processed, mix)
  when "hi8_chroma_noise"    then hi8_chroma_noise(processed, mix)
  when "double_exposure"     then double_exposure(processed, p[:second_image], p.fetch(:blend_mode, "over"))
  when "polaroid_frame"      then polaroid_frame(processed, level, p.fetch(:border_style, "classic"))
  when "tape_degradation"    then tape_degradation(processed, level)
  when "frame_distortion"    then frame_distortion(processed, level)
  when "super8_flicker"      then super8_flicker(processed, level)
  when "cinemascope_bars"    then cinemascope_bars(processed, level, p.fetch(:aspect_ratio, "2.35:1"))
  when "halftone_print"      then halftone_print(processed, level)
  when "film_scratches"      then film_scratches(processed, level)
  when "film_stock_emulation" then film_stock_emulation(processed, level, p.fetch(:stock, "kodak_portra"))
  when "sprocket_holes"      then sprocket_holes(processed, level)
  when "lens_flare"          then lens_flare(processed, level)
  when "vhs_degrade"         then vhs_degrade(processed, level)
  when "color_fade"          then color_fade(processed, level)
  when "anamorphic_simulation" then anamorphic_simulation(processed, level)
  when "soft_focus"          then soft_focus(processed, level)
  when "film_grain"          then film_grain(processed, level)
  when "film_halation"       then film_halation(processed, level)
  when "bloom_effect"        then bloom_effect(processed, level)
  when "cross_process"       then cross_process(processed, level)
  when "golden_hour_glow"    then golden_hour_glow(processed, level)
  when "lomo"                then lomo(processed, level)
  when "sepia"               then sepia(processed, level)
  when "teal_and_orange"     then teal_and_orange(processed, level)
  when "glitch"              then glitch(processed, level)
  when "dilla_head_bump"      then dilla_head_bump(processed, mix)
  when "dilla_tape_saturation" then dilla_tape_saturation(processed, level)
  when "dilla_vinyl_bandlimit" then dilla_vinyl_bandlimit(processed, level)
  when "dilla_phasy"          then dilla_phasy(processed, level)
  when "dilla_console_sum"    then dilla_console_sum(processed, level)
  else
    # Was a bare `else processed` — an fx name with no arm here returned
    # the image untouched, and the dmesg line below then reported the
    # step as having run. A preset could be four steps short of what
    # it says it is and the log would agree with the preset.
    message = "fx=#{fx} has no implementation; #{owner} is short a step"
    PostproBootstrap.dmesg "ERROR #{message}"
    raise ArgumentError, message
  end
end

# `stock:` swaps the film under an otherwise unchanged chain, which is how the
# stock sheet shows one grade on every emulsion.
def preset(image, name, stock: nil)
  p = PRESETS[name.to_sym] or
    raise ArgumentError, "unknown preset #{name.inspect}; have #{PRESETS.keys.join(', ')}"

  p = p.merge(stock:) if stock
  processed = image
  t_start = Time.now
  n_steps = p[:fx].length
  head = source_headroom(image)
  # Headroom on, for the whole chain. Values may exceed 0..255 between steps and
  # only the final clamp decides what becomes white.
  $postpro_float_pipeline = true
  PostproBootstrap.dmesg "preset=#{name} stock=#{p[:stock]} steps=#{n_steps} intensity=#{p[:intensity]}"
  if head[:reading]
    PostproBootstrap.dmesg format("source %s -> blur x%.2f curve x%.2f",
                                  head[:reading], head[:blur], head[:curve])
  end

  p[:fx].each_with_index do |fx, i|
    t0 = Time.now
    # What the picture looked like before this step, when asked. POSTPRO_EXPLAIN=1
    # turns the dmesg line below into a report of what each effect actually did,
    # rather than only that it ran.
    #
    # This file already carries the reason: an fx name with no arm in the case
    # returned the image untouched while the log reported the step as having run,
    # so a preset could be four steps short of what it says it is and the log
    # would agree with the preset. That was fixed for the missing-arm case. It
    # does not cover the arm that exists, runs, and changes nothing — which looks
    # identical from outside.
    before_stats = PostproExplain.snapshot(processed)
    processed = grade_step(fx, processed, p, head, "preset #{name}")
    processed = processed.copy_memory
    GC.start(full_mark: false) if (i % 4).zero?
    PostproBootstrap.dmesg "fx=#{fx} step=#{i + 1}/#{n_steps} time=%.3fs%s" %
                           [(Time.now - t0), PostproExplain.delta(before_stats, processed)]
  end

  PostproBootstrap.dmesg "preset=#{name} done total=%.2fs" % (Time.now - t_start)
  # The single clamp. Everything above ran in unbounded float; this is where
  # the negative becomes a print.
  $postpro_float_pipeline = false
  safe_cast(processed)
ensure
  # One clamp, at the end, whatever happened in between — including a raise,
  # which is why this is an ensure rather than a line before the return. Leaving
  # the flag set would make every later bare effect call return unbounded float
  # to a caller expecting 8-bit.
  $postpro_float_pipeline = false
end
