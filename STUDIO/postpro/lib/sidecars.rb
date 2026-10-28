# frozen_string_literal: true

# Main Workflow
def get_input
  $cli_logger.info "postpro.rb v18.0.0 full-analog#{REPLICATE_PRESENT ? " replicate=active" : ""}"

  check_replicate if REPLICATE_PRESENT

  if PROMPT
    workflow = PROMPT.select("Choose workflow:", [
      "Masterpiece Presets (Recommended)",
      "Random Effects (Experimental)",
      "Custom JSON Recipe",
    ])

    patterns = PROMPT.ask("File patterns:", default: "**/*.{jpg,jpeg,png,webp}").strip.split(",").map(&:strip)
    variations = PROMPT.ask("Variations per image:", convert: :int, default: CONFIG["variations"] || 7) { |q| q.in("5-10") }

    case workflow
    when "Masterpiece Presets (Recommended)"
      preset_name = PROMPT.select("Choose preset:", PRESETS.keys)
      [patterns, variations, { type: :preset, preset: preset_name }]

    when "Random Effects (Experimental)"
      mode = PROMPT.select("Mode:", %w[Professional Experimental])
      fx_count = PROMPT.ask("Effects per variation:", convert: :int, default: 4) { |q| q.in("2-8") }
      [patterns, variations, { type: :random, mode: mode.downcase, fx: fx_count }]

    when "Custom JSON Recipe"
      file = PROMPT.ask("Recipe file path:").strip
      recipe_data = File.exist?(file) ? JSON.parse(File.read(file)) : {}
      [patterns, variations, { type: :recipe, recipe: recipe_data }]
    end
  else
    # Fallback mode without tty-prompt
    patterns = ["**/*.{jpg,jpeg,png,webp}"]
    variations = CONFIG["variations"] || 7
    preset_name = CONFIG["default_preset"] || "house"
    [patterns, variations, { type: :preset, preset: preset_name }]
  end
end

def auto_mode
  PostproBootstrap.dmesg "auto mode enabled"
  patterns = ["**/*.{jpg,jpeg,png,webp}"]
  variations = CONFIG["variations"] || 7
  preset_name = CONFIG["default_preset"] || "house"

  [patterns, variations, { type: :preset, preset: preset_name }]
end

def postpro_quality_report(original, processed, reference_path = nil)
  before = rgb_bands(original).cast("float")
  after = rgb_bands(processed).cast("float")
  report = {
    dimensions: [processed.width, processed.height],
    mean_rgb_before: before.bandsplit.map { |band| band.avg.round(3) },
    mean_rgb_after: after.bandsplit.map { |band| band.avg.round(3) },
    clipped_highlights_percent: (((after >= 254).avg / 255.0) * 100).round(4),
    crushed_blacks_percent: (((after <= 1).avg / 255.0) * 100).round(4),
    warnings: [],
  }
  report[:warnings] << "highlight clipping exceeds 0.5%" if report[:clipped_highlights_percent] > 0.5
  report[:warnings] << "black clipping exceeds 0.5%" if report[:crushed_blacks_percent] > 0.5
  if reference_path && File.file?(reference_path)
    reference = rgb_bands(load_image(reference_path)).resize(processed.width.to_f / load_image(reference_path).width,
                                                              vscale: processed.height.to_f / load_image(reference_path).height)
    report[:reference_mean_absolute_error] = (after - reference.cast("float")).abs.avg.round(4)
  end
  report
rescue StandardError => e
  { warnings: ["quality analysis unavailable: #{e.message}"] }
end

# A sidecar another tool wrote keeps its fields and gains this one's under
# "postpro". replicate grades in place and hands over the path whose .json
# already holds the prompt, model and seed; replacing that file left the graded
# picture with a record of its grade and none of how it was made. A sidecar
# postpro wrote itself, or one that does not parse, is replaced.
def write_sidecar(output_path, data)
  path = "#{output_path}.json"
  existing = File.file?(path) ? JSON.parse(File.read(path)) : nil
  foreign = existing.is_a?(Hash) && !existing["schema"].to_s.start_with?("postpro.")
  File.write(path, JSON.pretty_generate(foreign ? existing.merge("postpro" => data) : data) + "\n")
  data
rescue JSON::ParserError
  File.write(path, JSON.pretty_generate(data) + "\n")
  data
end

# Which grade made a frame, as the hash of the code that graded it.
#
# The house look changes: a stock's curve is re-fitted, a step leaves `house`.
# A version somebody has to remember to bump is stale the first time they
# forget, and the recipe alone names effects whose arithmetic lives in this
# file. The digest of postpro.rb and its lib/ cannot drift from the grade, so a
# frame whose sidecar carries it can be re-graded identically by checking out
# the commit whose files hash to it.
GRADE_VERSION = Digest::SHA256.hexdigest(
  [POSTPRO_ENTRY, *Dir[File.join(POSTPRO_DIR, "*.rb"), File.join(POSTPRO_DIR, "lib", "*.rb")].sort].uniq.map { |path| File.binread(path) }.join,
)[0, 12].freeze

# The four uncanny numbers on the picture that went in and the one that came
# out, so a sidecar says which way the grade moved texture and clipping without
# anyone re-reading two files.
def uncanny_readings(original, processed)
  { before: Postpro::Uncanny.read_image(rgb_bands(original)).to_h,
    after: Postpro::Uncanny.read_image(rgb_bands(processed)).to_h }
rescue StandardError => e
  { unavailable: e.message }
end

# `presets` is one name, or the two uplift stacks, in the order they ran.
def write_grade_sidecar(input_path, output_path, presets, original, processed)
  names = Array(presets).map(&:to_sym)
  report = postpro_quality_report(original, processed, argv_flag("--reference"))
  data = {
    schema: "postpro.grade.v2",
    generated_at: Time.now.utc.iso8601,
    input: File.expand_path(input_path),
    output: File.expand_path(output_path),
    preset: names.join("+"),
    recipe: names.map { |name| PRESETS.fetch(name) },
    grade_version: GRADE_VERSION,
    seed: $postpro_seed,
    input_sha256: (Digest::SHA256.file(input_path).hexdigest if File.file?(input_path)),
    output_sha256: Digest::SHA256.file(output_path).hexdigest,
    quality: report,
    quality_analysis: {
      before: Postpro::QualityAnalyzer.report_image(original),
      after: Postpro::QualityAnalyzer.report_image(processed),
      interpretation: "sampled pixel diagnostics only; does not score composition, focus or intent"
    },
    uncanny: uncanny_readings(original, processed),
    capabilities: Studio::AnalogCapabilities.for(:postpro).map { |entry| entry[:id] },
  }
  write_sidecar(output_path, data)
end

def write_chain_sidecar(input_path, output_path, chain, take: nil, original: nil, processed: nil)
  data = {
    schema: "postpro.chain.v1",
    generated_at: Time.now.utc.iso8601,
    input: File.expand_path(input_path),
    output: File.expand_path(output_path),
    input_sha256: (Digest::SHA256.file(input_path).hexdigest if File.file?(input_path)),
    output_sha256: (Digest::SHA256.file(output_path).hexdigest if File.file?(output_path)),
    grade_version: GRADE_VERSION,
    seed: $postpro_seed,
    take: take&.number,
    look: take&.look&.to_s,
    lane: (take&.lane || random_chain_lane(chain)).to_s,
    chain: chain.map { |fx, params| { fx => params } },
  }
  if original && processed
    data[:quality] = postpro_quality_report(original, processed, argv_flag("--reference"))
    data[:uncanny] = uncanny_readings(original, processed)
  end
  write_sidecar(output_path, data)
rescue StandardError => e
  $logger.error "chain sidecar: #{e.message}"
end

def write_comparison(original, processed, output_path)
  return unless ARGV.include?("--compare")

  height = [original.height, processed.height].min
  left = original.thumbnail_image(height, height:, size: :down)
  right = processed.thumbnail_image(height, height:, size: :down)
  comparison = Vips::Image.arrayjoin([rgb_bands(left), rgb_bands(right)], across: 2, shim: 8,
                                                                       background: [24, 24, 24])
  path = output_path.sub(/(\.[^.]+)\z/, "-comparison\\1")
  comparison.write_to_file(path, Q: CONFIG["jpeg_quality"] || 95)
  path
end

# One-shot mode for programmatic use:
#   ruby postpro.rb --input in.jpg --output out.jpg --preset portrait
def one_shot_mode?
  argv_flag("--input") && argv_flag("--output") && argv_flag("--preset")
end

def introspect_mode?
  (ARGV & %w[--vocab-check --capabilities --list-presets --list-stocks --list-lenses --describe-preset --css-filter --export-lut --fit-grain --gallery --map]).any?
end
