# frozen_string_literal: true

RECIPE_ALLOWED = %w[
  grain film_curve highlight_roll shadow_lift micro_contrast color_separate
  chromatic_aberration vintage_lens split_toning split_grade bleach_bypass
  push_pull halation optical_blur tonemap dir_coupler spectral_temp color_temp
  skin_protect desaturate warmth green_push cross_fade infrared cyanotype
  lith_print technicolor kodachrome_sim faded_print base_tint dual_base_density
  reciprocity_failure bloom_pro teal_orange relight aerial_depth
  emulsion_defocus adjacency_effects longitudinal_ca lens_distortion bokeh_rendering
  anamorphic_flare diffraction_blur scan_noise newton_rings dust_and_hair
  film_curl_vignette selenium_tone dye_fade darkroom_print film_base_density
  paper_texture dodgeburn_artifacts fixing_bath_fog reticulation expired_film
  gate_weave lens_ghosting ortho_film tilt_shift stock_matrix
  adaptive_contrast film_shoulder clarity edge_aware_nr selective_sharpen
  vhs_luma_bleed vhs_chroma_delay vhs_head_switch_band vhs_tracking_noise
  vhs_interlace_comb crt_phosphor_bloom crt_scanlines minidv_block_dropout hi8_chroma_noise
  double_exposure polaroid_frame tape_degradation frame_distortion super8_flicker
  cinemascope_bars halftone_print film_scratches film_stock_emulation sprocket_holes
  lens_flare vhs_degrade color_fade anamorphic_simulation soft_focus
  film_grain film_halation bloom_effect cross_process golden_hour_glow lomo sepia
  teal_and_orange glitch dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit
  dilla_phasy dilla_console_sum
].freeze

# The stock a recipe step names, or the default when it names none it knows.
def recipe_stock(params, default = :kodak_portra)
  name = params["stock"]&.to_sym
  STOCKS.key?(name) ? name : default
end

# A recipe grades exactly as a preset does: every step through grade_step, so
# it gets the same per-effect mix, the same source-aware taper and the same
# float pipeline with one clamp at the end. It used to call each effect at its
# raw recipe number with none of the three, and that difference, not the
# effects, is what wrecked most random takes.
def recipe(image, recipe_data)
  head = source_headroom(image)
  $postpro_float_pipeline = true
  processed = recipe_data.reduce(image) do |picture, (fx, params)|
    # Evaluated per step, as preset does: left lazy, the take check and the
    # write each ran the whole nested gaussblur chain, so a chain cost twice.
    recipe_step(picture, fx, params, head).copy_memory
  end
  $postpro_float_pipeline = false
  safe_cast(processed)
ensure
  $postpro_float_pipeline = false
end

def recipe_step(image, fx, params, head)
  method = fx.gsub("_professional", "")
  unless RECIPE_ALLOWED.include?(method)
    $cli_logger.warn "recipe: #{fx} is not an allowed effect — skipped"
    return image
  end

  grade_step(method, image, recipe_preset(params), head, "recipe step #{fx}")
end

# A recipe step's numbers in the shape grade_step reads from a preset. A bare
# number is the intensity; the object form may also name a stock, a print
# stock, a temperature, stops, an exposure time, an age, a lens or a tonemap.
# nil.to_f is 0.0, so an object without "intensity" runs at 1.0: absent means
# default, not off.
def recipe_preset(params)
  opts = params.is_a?(Hash) ? params : {}
  intensity = params.is_a?(Hash) ? opts.fetch("intensity", 1.0).to_f : params.to_f
  {
    intensity:, stock: recipe_stock(opts),
    temp: (opts["target_kelvin"] || opts["kelvin"] || 5600).to_f,
    print_stock: PRINT_STOCKS.key?(opts["print_stock"]&.to_sym) ? opts["print_stock"].to_sym : nil,
    # A random push_pull step's number is its stops, as it always was.
    stops: (opts["stops"] || intensity).to_f,
    # Reciprocity failure is a function of time; a step's number picks a long
    # exposure of up to half a minute, a night frame rather than a star trail.
    exposure_secs: (opts["exposure_seconds"] || (1.0 + (intensity * 30.0))).to_f,
    age: (opts["age"] || intensity).to_f,
    lens: LENSES.key?((opts["lens"] || opts["type"]).to_s.to_sym) ? (opts["lens"] || opts["type"]).to_s : nil,
    tonemap: opts["tonemap"]&.to_sym, iso: opts["iso"],
    second_image: opts["second_image_path"] || opts["image"], blend_mode: opts["blend_mode"],
  }.compact
end

# Export a 3D LUT (.cube) for a preset. size³ lattice points; 17 is standard
# for color-grading workflows, 33 for higher precision.
def export_lut(preset_name, path, size = 17)
  step = 1.0 / (size - 1)
  lines = ["LUT_3D_SIZE #{size}", "DOMAIN_MIN 0.0 0.0 0.0", "DOMAIN_MAX 1.0 1.0 1.0", ""]
  size.times do |bi|
    size.times do |gi|
      size.times do |ri|
        pix = Vips::Image.black(1, 1, bands: 3) + [ri * step * 255, gi * step * 255, bi * step * 255]
        out = preset(pix.cast("uchar"), preset_name)
        ro = out.extract_band(0).avg / 255.0
        go = out.extract_band(1).avg / 255.0
        bo = out.extract_band(2).avg / 255.0
        lines << "%.6f %.6f %.6f" % [ro.clamp(0, 1), go.clamp(0, 1), bo.clamp(0, 1)]
      end
    end
  end
  File.write(path, lines.join("\n") + "\n")
  $cli_logger.info "LUT exported: #{path} (#{size}^3)"
rescue StandardError => e
  $cli_logger.error "export_lut failed: #{e.message}"
end

# A contact page of every render in a folder, written beside the renders it lists.
def write_gallery(directory)
  require "cgi"
  folder = File.expand_path(directory)
  names = Dir.glob(File.join(folder, "postpro_*.{jpg,jpeg,png}")).sort.map { |path| File.basename(path) }
  cells = names.map do |name|
    safe = CGI.escapeHTML(name)
    "<a href='#{safe}' style='width:320px'><img src='#{safe}' style='width:320px;display:block' loading=lazy>" \
      "<div>#{CGI.escapeHTML(name[0, 52])}</div></a>"
  end
  page = "<!doctype html><meta charset=utf-8><title>postpro renders</title>" \
         "<body style='margin:0;background:#111;color:#ccc;font:12px monospace'>" \
         "<div style='display:flex;flex-wrap:wrap;gap:4px;padding:4px'>#{cells.join}</div>"
  File.write(File.join(folder, "index.html"), page)
  $cli_logger.info "gallery: #{names.size} renders listed in #{File.join(folder, "index.html")}"
end

# Introspection
def describe_preset(name)
  p = PRESETS[name.to_sym] or return "unknown preset: #{name}"
  stock = STOCKS[p[:stock]]
  [
    "#{name}: #{p[:stock]} / #{p.fetch(:temp, "?")}K / intensity #{p[:intensity]}",
    "fx: #{p[:fx].join(" → ")}",
    stock ? "grain σ=#{stock[:grain]}" : nil,
  ].compact.join("\n")
end

def list_presets = PRESETS.keys.map { |k| describe_preset(k) }.join("\n\n")
def list_stocks = STOCKS.keys.join(", ")
def list_lenses = LENSES.keys.join(", ")

# CSS filter string approximating a preset — for lightweight web previews.
def css_filter(preset_name = :portrait)
  p = PRESETS[preset_name.to_sym] || PRESETS[:portrait]
  stock = STOCKS[p[:stock]] || {}
  hd = stock[:hd] || {}
  contrast = (1 + ((hd[:r]&.last || 1.0) - 1.0) * 0.25).round(2)
  saturate = if p[:fx].include?("teal_orange")
1.20
else
p[:fx].include?("desaturate")  ? 0.65 : 1.0
end
  parts = ["contrast(#{contrast})", "saturate(#{saturate})"]
  parts << "sepia(0.12)"    if %i[kodak_portra kodak_vision3_50d].include?(p[:stock])
  parts << "grayscale(0.9)" if p[:stock] == :tri_x
  parts.join(" ")
end

# Replicate Integration
def check_replicate
  return unless REPLICATE_PRESENT

  $cli_logger.info "Replicate detected! Auto-processing generated images..."

  recent_files = Dir.glob("*_generated_*.{jpg,jpeg,png,webp}")
                    .select { |f| File.mtime(f) > (Time.now - 300) }

  return unless recent_files.any?
    $cli_logger.info "Found #{recent_files.count} recent Replicate outputs"
    preset_name = PROMPT ? PROMPT.select("Choose preset for Replicate outputs:", PRESETS.keys) : (CONFIG["default_preset"] || "house")
    recent_files.each { |file| process_file(file, 2, preset_name) }

end

def preset_chain(image, names)
  names.reduce(image) { |img, name| preset(img, name) }
end

# The method whose `case fx` is the effect dispatch, read by --vocab-check.
EFFECT_DISPATCH = "grade_step"

# What one call of process_file grades: the source, its camera-corrected
# picture, and either a preset or a random recipe with the take it belongs to.
GradeRequest = Data.define(:file, :image, :preset_name, :recipe, :take)
