# frozen_string_literal: true

# Physics-ordered 6-8 step chains: optical_blur → exposure/temp → film_curve
# → chemistry → optical_effect → print → grain. One contrast mode and one
# color temperature approach per preset — no stacking.

# PRESETS is two literals merged in this order: the first half here and the
# rest in presets_more.rb, so neither file passes the 300-line cap.
PRESETS_FIRST_HALF = {
  # The house grade, and the default: the whole analog path rather than a
  # selection from it.
  #
  # Every other preset here is a look — a choice of some effects over others.
  # This one is the answer to "put the full treatment on it", which is what the
  # tool is for when nobody has asked for a particular film. Eighteen steps
  # against the ten of the richest preset before it.
  #
  # Ordered by where each thing physically happens, not by taste, because the
  # order is the difference between emulation and a stack of filters:
  #
  #   lens        optical_blur, vintage_lens, chromatic_aberration
  #   exposure    spectral_temp, halation      (halation is light reflecting off
  #                                            the film base back through the
  #                                            emulsion, so it precedes the curve)
  #   emulsion    emulsion_defocus             (dye layers sit at different depths)
  #   development film_curve, stock_matrix, dir_coupler, adjacency_effects
  #   negative    orange_mask
  #   print       print_film
  #   tone        skin_protect, shadow_lift, highlight_roll, micro_contrast
  #   grain       last, because it is a property of the emulsion the print sees
  #   gate        film_curl_vignette
  #
  # Safe as a default only because the source-aware scaling above exists: on a
  # photograph that already has texture and contrast, the defocus goes to zero
  # and the curve backs off, so eighteen steps do not mean eighteen
  # subtractions. Against a generated image it runs at full strength, which is
  # what a generated image needs.
  # Two effects are deliberately NOT in this chain, having been measured in it
  # and taken out. chromatic_aberration cost 0.0265 of texture and
  # film_curl_vignette 0.0428 — together two thirds of the picture's
  # micro-detail, and a vignette that dropped mean brightness by 53.8 levels.
  # Both are legitimate and both remain available to the presets that want
  # them; neither belongs in the one grade that runs when nobody chose.
  #
  # They are scaled now rather than merely excluded. When this was written the
  # taper reached only the defocus and the curve, and the paragraph above was
  # the only thing standing between a photograph and the damage — a note is not
  # a mechanism. head[:fringe] and head[:vignette] taper on texture, so the two
  # presets that want each still get them at a strength the source can afford.
  # Keeping them out of the default is a separate decision and it stands.
  #
  # NOTHING IN THIS CHAIN SOFTENS THE PICTURE.
  #
  # optical_blur, emulsion_defocus and vintage_lens are all out — the last one
  # took `lens:` with it, since it was that key's only reader and an unread key
  # is a --vocab-check failure. They are lens simulation, and lens simulation on
  # a frame that was already taken through a lens is invention, not emulation.
  # Softness is also the one artefact that cannot be undone downstream, which
  # makes it the wrong thing for a default to add on the operator's behalf.
  #
  # What is left is tone, colour and emulsion: the H&D curve, dye crosstalk,
  # coupler inhibition, adjacency, the negative's mask, the print stock, and
  # grain. Halation stays and is not a blur — it adds light that bounced off the
  # film base back through the emulsion, which is why it glows rather than
  # smears, and it measured at -0.0001 texture.
  #
  # This is the difference between a film emulation and a lo-fi filter. No lomo,
  # no scan lines, no vignette, no defocus.
  house: { fx: %w[spectral_temp halation film_curve stock_matrix dir_coupler
                  adjacency_effects orange_mask print_film skin_protect
                  shadow_lift highlight_roll micro_contrast grain],
           stock: :kodak_portra, print_stock: :kodak_2383,
           temp: 5400, intensity: 0.80 },

  portrait: { fx: %w[optical_blur spectral_temp film_curve dir_coupler orange_mask skin_protect shadow_lift highlight_roll grain],
              stock: :kodak_portra, temp: 5200, intensity: 0.85 },

  # `lens:` is not metadata: vintage_lens is the effect that reads it. Every
  # preset declaring a lens must include this step, or the look silently loses
  # its named optical character and falls back to an unrelated default.
  indie: { fx: %w[optical_blur spectral_temp vintage_lens film_curve orange_mask shadow_lift split_toning chromatic_aberration grain],
           stock: :kodak_portra, temp: 5400, intensity: 0.85, lens: "helios" },

  polaroid: { fx: %w[optical_blur spectral_temp film_curve faded_print warmth bloom_pro shadow_lift grain],
              stock: :kodak_portra, temp: 5000, intensity: 0.85 },

  landscape: { fx: %w[optical_blur vintage_lens spectral_temp halation film_curve stock_matrix color_separate
                      micro_contrast grain],
               stock: :fuji_velvia, temp: 5800, intensity: 0.90, lens: "zeiss" },

  magic_hour: { fx: %w[optical_blur spectral_temp halation film_curve warmth bloom_pro grain],
                stock: :fuji_velvia, temp: 4800, intensity: 0.90 },

  reversal: { fx: %w[optical_blur spectral_temp halation film_curve stock_matrix color_separate highlight_roll
                     micro_contrast grain],
              stock: :fuji_velvia, temp: 5600, intensity: 0.90 },

  process_e6: { fx: %w[optical_blur spectral_temp push_pull halation film_curve color_separate highlight_roll grain],
                stock: :ektachrome_100, temp: 5600, intensity: 0.90, stops: 2.0 },

  cinematic: { fx: %w[optical_blur spectral_temp halation tonemap film_curve orange_mask shadow_lift print_film grain],
               stock: :kodak_vision3_500t, temp: 4500, intensity: 0.90, print_stock: :kodak_2383 },

  blockbuster: { fx: %w[optical_blur spectral_temp halation tonemap bleach_bypass film_curve orange_mask teal_orange print_film grain],
                 stock: :kodak_vision3, temp: 4800, intensity: 0.90, print_stock: :kodak_2383 },

  golden_age: { fx: %w[optical_blur spectral_temp vintage_lens film_curve orange_mask technicolor warmth dir_coupler bloom_pro grain],
                stock: :kodak_vision3_50d, temp: 5200, intensity: 0.85, lens: "cooke" },

  bleached: { fx: %w[optical_blur spectral_temp tonemap bleach_bypass film_curve split_grade highlight_roll grain],
              stock: :kodak_vision3, temp: 4800, intensity: 0.90 },

  neon_night: { fx: %w[optical_blur spectral_temp push_pull reciprocity_failure halation film_curve orange_mask
                       bloom_pro grain],
                stock: :cinestill_800t, temp: 3200, intensity: 0.90,
                stops: 0.5, exposure_secs: 30.0 },

  tokyo_night: { fx: %w[optical_blur spectral_temp push_pull reciprocity_failure halation film_curve orange_mask
                        teal_orange grain],
                 stock: :cinestill_800t, temp: 3000, intensity: 0.90,
                 stops: 1.0, exposure_secs: 45.0 },

  tungsten: { fx: %w[optical_blur spectral_temp reciprocity_failure halation film_curve orange_mask push_pull
                     shadow_lift grain],
              stock: :kodak_vision3_500t, temp: 3200, intensity: 0.90,
              stops: 0.3, exposure_secs: 8.0 },

  street: { fx: %w[optical_blur spectral_temp tonemap bleach_bypass push_pull film_curve adjacency_effects shadow_lift micro_contrast grain],
            stock: :tri_x, temp: 5600, intensity: 0.90, stops: 1.0 },

  war_doc: { fx: %w[optical_blur spectral_temp tonemap push_pull film_curve bleach_bypass green_push grain],
             stock: :tri_x, temp: 5600, intensity: 0.90, stops: 2.0 },

  silver_gelatin: { fx: %w[optical_blur spectral_temp film_curve push_pull adjacency_effects shadow_lift highlight_roll grain],
                    stock: :tri_x, temp: 5600, intensity: 0.85, stops: 0.5 },

  lith: { fx: %w[optical_blur spectral_temp film_curve push_pull lith_print split_toning grain],
          stock: :tri_x, temp: 5600, intensity: 0.90, stops: 1.5 },

  noir: { fx: %w[optical_blur spectral_temp tonemap push_pull film_curve bleach_bypass desaturate shadow_lift grain],
          stock: :tri_x, temp: 5600, intensity: 0.90, stops: 2.0 },

  dream: { fx: %w[optical_blur spectral_temp vintage_lens halation film_curve bloom_pro desaturate split_toning grain],
           stock: :ektachrome_100, temp: 5800, intensity: 0.85, lens: "leica" },

  dreamscape: { fx: %w[optical_blur spectral_temp halation film_curve bloom_pro split_toning grain],
                stock: :ektachrome_100, temp: 5800, intensity: 0.85 },

  lo_fi: { fx: %w[optical_blur spectral_temp vintage_lens film_curve push_pull faded_print warmth chromatic_aberration grain],
           stock: :kodak_portra, temp: 4800, intensity: 0.85, lens: "helios" },

  horror: { fx: %w[optical_blur spectral_temp tonemap film_curve bleach_bypass green_push desaturate grain],
            stock: :tri_x, temp: 5600, intensity: 0.90 },

  arctic: { fx: %w[optical_blur spectral_temp tonemap film_curve desaturate bleach_bypass highlight_roll grain],
            stock: :tri_x, temp: 6500, intensity: 0.90 },

  kodachrome_look: { fx: %w[optical_blur spectral_temp halation tonemap film_curve stock_matrix kodachrome_sim dir_coupler grain],
                     stock: :kodachrome, temp: 5600, intensity: 0.90 },

  technicolor_3strip: { fx: %w[optical_blur spectral_temp film_curve stock_matrix technicolor dir_coupler bloom_pro grain],
                        stock: :kodachrome, temp: 5500, intensity: 0.90 },

  cross_process: { fx: %w[optical_blur spectral_temp push_pull film_curve color_separate teal_orange split_toning grain],
                   stock: :fuji_velvia, temp: 5500, intensity: 0.90, stops: 0.5 },

  vintage_chrome: { fx: %w[optical_blur film_curve stock_matrix dir_coupler spectral_temp color_separate split_toning grain],
                    stock: :ektachrome_100, temp: 5200, intensity: 0.85 },

  infrared_look: { fx: %w[optical_blur spectral_temp push_pull infrared film_curve bleach_bypass highlight_roll grain],
                   stock: :tri_x, temp: 5600, intensity: 0.90, stops: 0.5 },

  cyanotype_look: { fx: %w[optical_blur spectral_temp film_curve desaturate cyanotype shadow_lift grain],
                    stock: :tri_x, temp: 6000, intensity: 0.85 },

  analog_scan: { fx: %w[optical_blur spectral_temp film_curve grain scan_noise dust_and_hair newton_rings],
                 stock: :kodak_portra, temp: 5200, intensity: 0.80 },

  aged_chrome: { fx: %w[optical_blur spectral_temp film_curve dye_fade selenium_tone faded_print grain],
                 stock: :ektachrome_100, temp: 5600, intensity: 0.85, age: 0.60 },

  # LENSES[:anamorphic] was the one entry in that table no preset reached at
  # all. The preset named after it is the obvious home for it.
  anamorphic: { fx: %w[optical_blur vintage_lens longitudinal_ca spectral_temp halation tonemap film_curve anamorphic_flare grain],
                stock: :kodak_vision3_500t, temp: 4200, intensity: 0.90, lens: "anamorphic" },
}.freeze
