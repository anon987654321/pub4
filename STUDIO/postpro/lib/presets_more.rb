# frozen_string_literal: true

# The second half of the preset table; presets.rb holds the first.
PRESETS = PRESETS_FIRST_HALF.merge({
  contact_print: { fx: %w[optical_blur spectral_temp adjacency_effects film_curve darkroom_print shadow_lift grain],
                   stock: :tri_x, temp: 5600, intensity: 0.85 },

  aged_kodachrome: { fx: %w[optical_blur spectral_temp film_curve dye_fade kodachrome_sim dir_coupler grain],
                     stock: :kodachrome, temp: 5600, intensity: 0.88, age: 0.50 },

  wide_angle: { fx: %w[optical_blur lens_distortion spectral_temp halation film_curve grain],
                stock: :fuji_velvia, temp: 5800, intensity: 0.90, k1: -0.14 },

  cinema_scan: { fx: %w[optical_blur spectral_temp longitudinal_ca halation tonemap film_curve orange_mask bokeh_rendering print_film grain],
                 stock: :kodak_vision3, temp: 4600, intensity: 0.90, print_stock: :kodak_2383 },

  diffraction: { fx: %w[optical_blur spectral_temp diffraction_blur film_curve micro_contrast grain],
                 stock: :fuji_velvia, temp: 5600, intensity: 0.85, f_number: 22.0 },

  nitrate: { fx: %w[optical_blur spectral_temp film_curve dye_fade faded_print adjacency_effects grain scan_noise],
             stock: :kodachrome, temp: 4800, intensity: 0.85, age: 0.80 },

  fiber_print: { fx: %w[optical_blur spectral_temp adjacency_effects darkroom_print paper_texture dodgeburn_artifacts grain],
                 stock: :tri_x, temp: 5600, intensity: 0.85 },

  expired: { fx: %w[optical_blur spectral_temp film_curve expired_film gate_weave],
             stock: :kodak_portra, temp: 5200, intensity: 0.90, age: 0.65 },

  # The two presets below carry effects recovered from this file's first
  # generation. Added as NEW presets rather than folded into the fifty-eight
  # that existed at the time, because those were tuned looks and a recovered effect is
  # not a reason to move one.
  #
  # A cassette that has been opened, or a back that no longer seals. The leak
  # arrives from a frame edge and fogs the shadows first, so it belongs after
  # the curve — the fog is light the emulsion received, not a grade applied to
  # what it recorded.
  light_leak: { fx: %w[optical_blur spectral_temp halation film_curve light_leaks grain],
                stock: :kodak_portra, temp: 5600, intensity: 0.85 },

  # Daylight printed as moonlight. A convention rather than a process — real
  # moonlight is neither this blue nor this directional, and an audience reads
  # it as night because film has always shown it this way.
  day_for_night: { fx: %w[optical_blur spectral_temp film_curve day_for_night shadow_lift grain],
                   stock: :kodak_vision3_500t, temp: 4100, intensity: 0.85 },

  reticulated: { fx: %w[optical_blur spectral_temp film_curve reticulation fixing_bath_fog grain],
                 stock: :tri_x, temp: 5600, intensity: 0.80 },

  ortho: { fx: %w[optical_blur spectral_temp ortho_film film_curve adjacency_effects grain],
           stock: :tri_x, temp: 5600, intensity: 0.85 },

  tilt_shift_look: { fx: %w[optical_blur spectral_temp halation film_curve tilt_shift grain],
                     stock: :kodak_portra, temp: 5200, intensity: 0.80 },

  haunted: { fx: %w[optical_blur spectral_temp expired_film reticulation fixing_bath_fog lens_ghosting gate_weave grain],
             stock: :kodachrome, temp: 4600, intensity: 0.90, age: 0.80 },

  quality_uplift: { fx: %w[spectral_temp adaptive_contrast film_shoulder clarity edge_aware_nr selective_sharpen film_curve grain],
                    stock: :kodak_portra, temp: 5600, intensity: 0.75 },

  vhs_tape: { fx: %w[optical_blur spectral_temp vhs_luma_bleed vhs_chroma_delay vhs_tracking_noise vhs_interlace_comb vhs_head_switch_band],
              stock: :kodak_portra, temp: 6500, intensity: 0.80 },

  crt_broadcast: { fx: %w[optical_blur spectral_temp crt_phosphor_bloom crt_scanlines hi8_chroma_noise],
                   stock: :kodak_portra, temp: 6500, intensity: 0.75 },

  camcorder_glitch: { fx: %w[optical_blur spectral_temp vhs_chroma_delay minidv_block_dropout vhs_tracking_noise crt_scanlines],
                      stock: :kodak_portra, temp: 6500, intensity: 0.85 },

  # ==========================================================================
  # 2026-07-30. One preset per new stock and per new lens, so nothing added
  # above is reachable only by hand-editing a recipe.
  # ==========================================================================

  # HP5 in daylight, developed normally, printed straight. The plainest thing
  # this file can do, and there was no preset for it: every black-and-white
  # preset here bleaches, pushes, tones, solarises or otherwise intervenes.
  # print_stock: kodak_2302 is the black-and-white print film in PRINT_STOCKS,
  # and until this preset no chain projected onto it — the table had two entries
  # and one reader.
  reportage: { fx: %w[optical_blur spectral_temp vintage_lens film_curve adjacency_effects micro_contrast print_film grain],
               stock: :ilford_hp5, temp: 5600, intensity: 0.85, lens: "summicron", print_stock: :kodak_2302 },

  # Delta 3200 at night, which is the only place it makes sense. Grain is not a
  # side effect of this preset, it is the subject.
  available_darkness: { fx: %w[optical_blur spectral_temp film_curve push_pull shadow_lift adjacency_effects grain],
                        stock: :ilford_delta3200, temp: 3400, intensity: 0.90, stops: 1.5 },

  # Ektar, with the colour matrix doing the work its data was written for.
  saturated_negative: { fx: %w[optical_blur spectral_temp vintage_lens film_curve stock_matrix orange_mask color_separate micro_contrast grain],
                        stock: :kodak_ektar100, temp: 5500, intensity: 0.90, lens: "zeiss" },

  # Pro 400H: cool, pastel, and the only preset here that does not warm up.
  pastel_portrait: { fx: %w[optical_blur spectral_temp vintage_lens film_curve stock_matrix orange_mask skin_protect highlight_roll grain],
                     stock: :fuji_pro400h, temp: 6200, intensity: 0.80, lens: "soft_focus" },

  # An SX-70 print: milky blacks, a ceiling on the highlights, and the whole
  # thing a little faded before it has finished developing.
  instant_pack: { fx: %w[optical_blur spectral_temp film_curve stock_matrix faded_print film_base_density bloom_pro grain],
                  stock: :polaroid_sx70, temp: 5800, intensity: 0.85, age: 0.35 },

  # The Petzval swirl, as far as a per-pixel pipeline can carry it: centre
  # holding, everything else glowing and coming apart at the edges.
  swirl_portrait: { fx: %w[optical_blur spectral_temp vintage_lens film_curve orange_mask film_curl_vignette skin_protect grain],
                    stock: :kodak_portra, temp: 5200, intensity: 0.85, lens: "petzval" },

  # Uncoated pre-war glass: no anti-reflection coating, so every highlight
  # veils the shadows next to it and contrast is a suggestion.
  uncoated_glass: { fx: %w[optical_blur spectral_temp vintage_lens film_curve shadow_lift adjacency_effects grain],
                    stock: :ilford_hp5, temp: 5400, intensity: 0.85, lens: "uncoated" },

  # A plastic meniscus and expired consumer film, which is most of what the
  # word "lomo" ever meant.
  plastic_lens: { fx: %w[optical_blur spectral_temp vintage_lens film_curve expired_film film_curl_vignette grain],
                  stock: :fuji_pro400h, temp: 5000, intensity: 0.85, lens: "lomo", age: 0.5 },

  # Radioactive thorium glass yellows with age; a Takumar shot today is warmer
  # than the one that left the factory.
  takumar_sun: { fx: %w[optical_blur spectral_temp vintage_lens film_curve stock_matrix orange_mask warmth grain],
                 stock: :kodak_ektar100, temp: 5000, intensity: 0.85, lens: "takumar" },

  legacy_polaroid: { fx: %w[spectral_temp film_curve faded_print polaroid_frame], stock: :polaroid_sx70,
                     temp: 5800, intensity: 0.82 },

  legacy_super8: { fx: %w[spectral_temp film_curve super8_flicker film_scratches], stock: :kodak_vision3_50d,
                   temp: 5600, intensity: 0.78 },

  legacy_cinemascope: { fx: %w[spectral_temp halation film_curve print_film cinemascope_bars], stock: :kodak_vision3_500t,
                        temp: 4500, intensity: 0.78, print_stock: :kodak_2383 },

  legacy_halftone: { fx: %w[spectral_temp film_curve halftone_print], stock: :kodak_portra,
                     temp: 5400, intensity: 0.72 },

  legacy_vhs: { fx: %w[spectral_temp vhs_degrade], stock: :kodak_portra,
                temp: 6500, intensity: 0.72 },

  legacy_anamorphic: { fx: %w[spectral_temp halation film_curve print_film anamorphic_simulation], stock: :kodak_vision3_500t,
                       temp: 4200, intensity: 0.80, print_stock: :kodak_2383 },

  legacy_tape: { fx: %w[spectral_temp film_curve tape_degradation color_fade], stock: :kodak_portra,
                 temp: 5200, intensity: 0.70 },

  legacy_frame: { fx: %w[spectral_temp film_curve frame_distortion film_scratches], stock: :ilford_hp5,
                  temp: 5600, intensity: 0.70 },

  legacy_sprocket: { fx: %w[spectral_temp film_curve sprocket_holes], stock: :kodak_portra,
                     temp: 5400, intensity: 0.80 },

  legacy_flare: { fx: %w[spectral_temp film_curve lens_flare], stock: :kodak_vision3,
                  temp: 5400, intensity: 0.70 },

  legacy_soft_focus: { fx: %w[spectral_temp film_curve soft_focus grain], stock: :kodak_portra,
                       temp: 5200, intensity: 0.72 },

  legacy_scratch_print: { fx: %w[spectral_temp film_curve film_scratches color_fade], stock: :kodachrome,
                          temp: 5400, intensity: 0.68 },

  legacy_cross_process: { fx: %w[spectral_temp film_curve cross_process film_halation grain], stock: :fuji_velvia,
                          temp: 5500, intensity: 0.72 },

  legacy_golden_hour: { fx: %w[spectral_temp film_curve golden_hour_glow], stock: :kodak_portra,
                        temp: 4800, intensity: 0.72 },

  legacy_lomo: { fx: %w[spectral_temp vintage_lens film_curve lomo grain], stock: :fuji_pro400h,
                 temp: 5000, intensity: 0.70, lens: "lomo" },

  legacy_sepia: { fx: %w[spectral_temp film_curve sepia grain], stock: :ilford_hp5,
                  temp: 5400, intensity: 0.68 },

  legacy_glitch: { fx: %w[spectral_temp glitch], stock: :kodak_portra,
                   temp: 6500, intensity: 0.68 },

  dilla_vinyl_hot: { fx: %w[spectral_temp dilla_head_bump dilla_vinyl_bandlimit dilla_phasy grain],
                     stock: :kodak_portra, temp: 5000, intensity: 0.72 },

  dilla_summing_phasy: { fx: %w[spectral_temp dilla_head_bump dilla_phasy film_curve grain],
                         stock: :kodak_ektar100, temp: 5200, intensity: 0.70 },

  dilla_tape: { fx: %w[spectral_temp dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit grain],
                stock: :kodak_vision3_500t, temp: 4700, intensity: 0.74 },

  dilla_acetate: { fx: %w[spectral_temp dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit film_curve],
                   stock: :fuji_pro400h, temp: 4900, intensity: 0.68 },
}).freeze
