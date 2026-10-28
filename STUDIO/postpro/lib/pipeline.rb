# frozen_string_literal: true

# Grades `file` `variations` times through a preset or a random recipe and
# returns how many variations were written. `take` is the RandomTake a random
# run is drawing, or nil for every other caller.
def process_file(file, variations, preset_name = nil, recipe_data = nil, take: nil)
  image = load_image(file)
  return 0 unless image

  request = GradeRequest.new(file:, image: camera_corrected(image, file), preset_name:, recipe: recipe_data, take:)
  written, failed = write_variations(request, variations)
  refuse_failed_family!(file, variations, failed) if written.zero? && failed.positive?
  written
end

# The body's own colour response, before anything else touches the picture.
#
# ON BY DEFAULT, and set false only by someone who has a reason. It was
# `if CONFIG["apply_camera_profile_first"]` against a CONFIG that is {} unless
# a master.json exists, so the answer was nil on every invocation this file
# has ever had — fifty lines of matching and matrix application that had never
# run, aimed at a profiles directory that had never existed.
#
# Both halves are real now: camera_profiles.json holds 121 bodies across
# six vendors, recovered from a VSCO DCP archive. A default of off would have
# kept them as decorative as the code that reads them.
#
# It no-ops safely on anything without EXIF Make/Model, which is every
# generated image — so a render is unaffected and a photograph is corrected.
def camera_corrected(image, file)
  return image if CONFIG.fetch("apply_camera_profile_first", true) == false

  profile = get_camera_profile(image)
  return image unless profile

  corrected = apply_camera_profile(image, profile)
  PostproBootstrap.dmesg "camera_profile src=#{File.basename(file)}"
  corrected
end

# Every variation is attempted; one that raises costs only itself. Returns the
# number written and the number that failed.
def write_variations(request, variations)
  failed = 0
  written = variations.times.count do |index|
    write_variation(request, index)
  rescue StandardError => e
    failed += 1
    report_failed_variation(index + 1, e)
    false
  end
  [written, failed]
end

# One variation: grade, finish, name, write, record. Returns the path written,
# or nil when there was nothing to grade.
def write_variation(request, index)
  processed = graded_variation(request)
  return unless processed

  output = variation_output_path(request, index)
  Postpro::Constitution.verify_chain!(chain: request.recipe, stage_rank: random_stage_rank) if request.recipe
  quality = CONFIG["jpeg_quality"] || 95
  write_graded_image(processed, output, quality)
  write_variation_sidecar(request, output, processed)
  PostproBootstrap.dmesg "write out=#{File.basename(output)} q=#{quality}"
  output
end

# The grade itself, then the finish every variation shares: the tone anchor,
# the survival check a random take must pass, the last grain, and three bands.
# Grain lands last, on the exposure the take will be seen at: lifting the shadows
# after it amplified the grain there, threefold in a dark face.
def graded_variation(request)
  return preset_variation(request) if request.preset_name
  return unless request.recipe

  balanced = balance_source(request.image)
  grains, body = request.recipe.partition { |step| step.first.to_s == RANDOM_ALWAYS }
  processed = settle_exposure(anchor_tones(recipe(balanced, body)), balanced:, request:)
  check_take_survives!(processed, request.image, request.take&.look)
  rgb_bands(finish_with_grain(processed, grains))
end

# Day for night darkens on purpose: holding its exposure to the source's undid
# the one thing the look is for.
EXPOSURE_LOOKS = %w[day_for_night].freeze

def exposure_is_the_look?(request)
  return true if EXPOSURE_LOOKS.include?(request.take&.look.to_s)

  request.recipe.any? { |step| EXPOSURE_LOOKS.include?(step.first.to_s) }
end

def settle_exposure(processed, balanced:, request:)
  exposure_is_the_look?(request) ? processed : hold_exposure(processed, balanced)
end

# Grain should be felt rather than seen: a random take's grain runs at no more
# than RANDOM_GRAIN_CAP, where a look's own figure (0.9 for most) or a loud lane
# (up to 0.88) printed it as noise.
RANDOM_GRAIN_CAP = 0.45

def finish_with_grain(processed, grains)
  return apply_finishing_grain(processed, nil, grained: false) if grains.empty?

  recipe(processed, grains.map { |fx, params| [fx, capped_grain(params)] })
end

def capped_grain(params)
  return [params.to_f, RANDOM_GRAIN_CAP].min unless params.is_a?(Hash)

  params.merge("intensity" => [params.fetch("intensity", 1.0).to_f, RANDOM_GRAIN_CAP].min)
end

def preset_variation(request)
  processed = anchor_tones(preset(request.image, request.preset_name))
  rgb_bands(apply_finishing_grain(processed, request.preset_name, grained: nil))
end

# Balance before the look, as a colourist does: a look graded onto a frame that
# is off in white balance or exposure carries the error into every take. Only
# part of the way to neutral and to mid grey, and never further than
# BALANCE_MAX_CAST or BALANCE_MAX_EV, because a warm or a low-key frame may be
# that way on purpose.
BALANCE_SHARE = 0.5
BALANCE_MAX_CAST = 8.0
BALANCE_MAX_EV = 0.75
BALANCE_NEUTRAL_CHROMA = 10.0
MID_GREY = 0.18

def balance_source(image)
  expose_toward_grey(neutralise(rgb_bands(image).cast(:uchar).copy(interpretation: :srgb)))
rescue StandardError => e
  $logger.error "balance_source: #{e.message}"
  image
end

# Gray world on what is nearly grey already: the mean a* and b* of the
# near-neutral pixels is the cast, and half of it comes out.
def neutralise(image)
  lightness, red_green, yellow_blue = image.colourspace(:lab).bandsplit
  chroma = ((red_green * red_green) + (yellow_blue * yellow_blue))**0.5
  neutral = (chroma < BALANCE_NEUTRAL_CHROMA) & (lightness > 20) & (lightness < 90)
  shifts = [red_green, yellow_blue].map { |band| masked_mean(band, neutral, 0.05) }
  return image if shifts.any?(&:nil?)

  a_shift, b_shift = shifts.map { |mean| (-mean * BALANCE_SHARE).clamp(-BALANCE_MAX_CAST, BALANCE_MAX_CAST) }
  lightness.bandjoin([red_green + a_shift, yellow_blue + b_shift]).copy(interpretation: :lab)
           .colourspace(:srgb).cast(:uchar)
end

# Part of the way toward a mid-grey median, in linear light, with a shoulder so
# a lifted highlight rolls instead of clipping.
def expose_toward_grey(image)
  median = HD.srgb_to_linear(image.colourspace("b-w").extract_band(0).percent(50) / 255.0)
  return image if median <= 1e-4

  ev = (Math.log2(MID_GREY / median) * BALANCE_SHARE).clamp(-BALANCE_MAX_EV, BALANCE_MAX_EV)
  return image if ev.abs < 0.05

  exposed = push_shoulder(image.colourspace("scrgb") * (2.0**ev))
  safe_cast(clamp01(exposed).colourspace("srgb"))
end

# A look moves palette and contrast; it should not move exposure. Measured on
# nine photographs, takes drifted darker than their source, faces first. This
# bends the graded luminance so its median returns to the reference's, with
# black and white held (a power curve on 0..1) and every channel scaled by the
# same ratio, so hue holds.
EXPOSURE_HOLD_RANGE = (0.6..1.6)

def hold_exposure(graded, reference)
  target = luma_median(reference)
  current = luma_median(graded)
  return graded if target <= 0.01 || current <= 0.01 || current >= 0.99 || (target - current).abs < 0.01

  gamma = (Math.log(target) / Math.log(current)).clamp(EXPOSURE_HOLD_RANGE.first, EXPOSURE_HOLD_RANGE.last)
  luma = clamp01(graded.colourspace("b-w").extract_band(0).cast(:float) / 255.0)
  lifted = (luma > 1e-4).ifthenelse(luma, 1e-4)
  ratio = (lifted**gamma) / lifted
  safe_cast(clamp01(graded.cast(:float) / 255.0 * ratio.bandjoin([ratio, ratio])) * 255.0)
end

def luma_median(image) = rgb_bands(image).colourspace("b-w").extract_band(0).cast(:uchar).percent(50) / 255.0

# Built from dirname + basename, not String#sub on the extension: sub matches
# the first occurrence anywhere in the path, so a directory component
# containing the extension (shoots/2024.jpg/frame.jpg) was rewritten and the
# write went to a path that does not exist.
def variation_output_path(request, index)
  file = request.file
  ext = File.extname(file)
  safe_stem = File.basename(file, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
  output_ext = ARGV.include?("--tiff16") ? ".tif" : ext
  name = "postpro_#{safe_stem}_#{variation_suffix(request)}_v#{index + 1}#{output_ext}"
  output = Postpro::Constitution.available_output_path(File.join(Postpro::Constitution.output_dir_for(file), name))
  Postpro::Constitution.verify_output!(input_path: file, output_path: output)
  output
end

def variation_suffix(request)
  return request.preset_name.to_s if request.preset_name

  request.recipe ? random_take_label(request.recipe, request.take) : "processed"
end

def write_graded_image(processed, output, quality)
  if ARGV.include?("--tiff16") || output.end_with?(".tif", ".tiff")
    processed.cast("ushort").write_to_file(output)
  else
    processed.write_to_file(output, Q: quality)
  end
end

# A random chain cannot be looked up again at all, so its recipe goes out
# beside the picture or it is gone. A preset can, but its tables change, so the
# grade's version and what it did to the picture go out too.
def write_variation_sidecar(request, output, processed)
  if request.recipe
    write_chain_sidecar(request.file, output, request.recipe, take: request.take)
  else
    write_grade_sidecar(request.file, output, request.preset_name, request.image, processed)
  end
end

def report_failed_variation(number, error)
  message = error.message
  $logger.error "Variation #{number} failed: #{message} at #{error.backtrace&.first(4)&.join(' <- ')}"
  $cli_logger.error "Variation #{number} failed: #{message}"
end

# run_random reads the "all " at the front of this message as a take that
# destroyed the picture, and draws that take again on another look.
def refuse_failed_family!(file, variations, failed)
  raise "all #{failed}/#{variations} variations failed for #{File.basename(file)}; no output was written"
end
