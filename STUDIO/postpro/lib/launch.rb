# frozen_string_literal: true

# The older behaviour, kept because stacking two presets is a different and
# still useful thing: it asks what the house grade does twice, where a random
# chain asks what the emulsion can do at all.
def run_uplift(dir, files)
  presets = PRESETS.keys.shuffle
  count = (argv_flag("--count") || argv_flag("-n") || 4).to_i.clamp(1, 6)
  PostproBootstrap.dmesg "uplift dir=#{dir} files=#{files.count}"
  files.each_with_index do |file, index|
    $cli_logger.info "#{index + 1}/#{files.count}: #{File.basename(file)}"
    count.times do |i|
      base = presets[(index + i) % presets.size]
      layer = (presets - [base]).sample
      image = load_image(file)
      next unless image
      image = camera_corrected(image, file)

      processed = rgb_bands(apply_finishing_grain(preset_chain(image, [base, layer]), base))
      ext = File.extname(file)
      safe_stem = File.basename(file, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
      output = File.join(Postpro::Constitution.output_dir_for(file),
                         "postpro_#{safe_stem}_#{base}+#{layer}_v#{i + 1}#{ext}")
      output = Postpro::Constitution.available_output_path(output)
      Postpro::Constitution.verify_output!(input_path: file, output_path: output)
      processed.write_to_file(output, Q: CONFIG["jpeg_quality"] || 95)
      write_grade_sidecar(file, output, [base, layer], image, processed)
      PostproBootstrap.dmesg "write chain=#{base}+#{layer} out=#{File.basename(output)}"
    end
    GC.start if (index % 5).zero?
  rescue StandardError => e
    $cli_logger.error "Error #{File.basename(file)}: #{e.message}"
  end
end

def run_watch
  dir = argv_flag("--watch") || "/sdcard/DCIM/Camera"
  preset_name = (argv_flag("--preset") || "cinematic").to_sym
  unless PRESETS.key?(preset_name)
    $cli_logger.error "Unknown preset: #{preset_name}"
    exit 1
  end
  # The output name matches the input glob, and run_watch carried none of the
  # reject guard the other two batch paths use, so every graded file was seen
  # as new and graded again: one seed image produced fourteen nested
  # generations in thirty seconds, on a directory that is a phone camera roll.
  already_graded = Regexp.union(PRESETS.keys.map(&:to_s) + %w[processed masterpiece postpro])
  watch_glob = lambda do
    Dir.glob(File.join(dir, "IMG_*.{jpg,jpeg,JPG,JPEG}"))
       .reject { |f| File.basename(f).match?(already_graded) || File.basename(f).match?(/_v\d+_/) }
  end
  seen = watch_glob.call.map { |f| [f, File.mtime(f)] }.to_h
  PostproBootstrap.dmesg "watch dir=#{dir} preset=#{preset_name} known=#{seen.size}"
  loop do
    sleep 2
    watch_glob.call.each do |path|
      mtime = File.mtime(path)
      next if seen[path] == mtime
      seen[path] = mtime
      next if File.size(path) < 50_000
      ext = File.extname(path)
      base = File.basename(path, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
      out = File.join(Postpro::Constitution.output_dir_for(path), "postpro_#{base}_#{preset_name}#{ext}")
      out = Postpro::Constitution.available_output_path(out)
      Postpro::Constitution.verify_output!(input_path: path, output_path: out)
      PostproBootstrap.dmesg "new path=#{File.basename(path)} -> #{File.basename(out)}"
      begin
        grade_watched(path, out, preset_name)
        $cli_logger.info "ok preset=#{preset_name} out=#{out}"
      rescue StandardError => e
        $cli_logger.error "watch error: #{e.message}"
      end
    end
  end
end

# One photograph off the camera roll, graded and recorded. Out of the watch loop
# so a single arrival can be graded without a loop that never returns.
def grade_watched(path, out, preset_name)
  image = load_image(path)
  return unless image

  image = camera_corrected(image, path)
  processed = rgb_bands(apply_finishing_grain(anchor_tones(preset(image, preset_name)), preset_name))
  processed.write_to_file(out, Q: CONFIG["jpeg_quality"] || 95)
  write_grade_sidecar(path, out, preset_name, image, processed)
end

def run_quality_analysis
  input_path = argv_flag("--quality")
  unless input_path && File.file?(input_path) && File.readable?(input_path)
    $cli_logger.error "quality: --quality needs a readable image file"
    exit 2
  end

  image = load_image(input_path)
  unless image
    $cli_logger.error "quality: could not decode #{input_path}"
    exit 2
  end

  puts JSON.pretty_generate(Postpro::QualityAnalyzer.report_image(image))
end

def validate_postpro_style_contract
  name = argv_flag("--style-contract")
  return unless name

  entry = Studio::StyleRegistry.resolve(style_id: name, modality: "image")
  $postpro_style_contract = {
    id: entry["style_id"], version: entry["version"], modality: entry["modality"],
    registry_sha256: Digest::SHA256.file(Studio::StyleRegistry::REGISTRY_PATH).hexdigest,
    mapping_applied: false,
    note: "contract validated and recorded; renderer parameters are not yet compiled from this entry"
  }
rescue Studio::StyleRegistry::InvalidStyle => e
  $cli_logger.error "style contract rejected: #{e.message}"
  exit 2
end

def auto_launch
  validate_postpro_style_contract
  return run_quality_analysis if ARGV.include?("--quality")
  return run_introspect if introspect_mode?
  return run_stock_sheet if ARGV.include?("--stock-sheet")
  return run_watch       if watch_mode?
  return run_one_shot    if one_shot_mode?
  return run_random_subjects(random_subjects) if random_mode?

  # A bare path is a subject, not a typo the menu swallows: an image gets the
  # chains --random would draw for it, a directory a few picks from it, and
  # several paths get one family each. A path that is neither file nor
  # directory is named and refused, because a menu opened on a typo reads as a
  # hang.
  subjects = positional_subjects

  return run_random_subjects(subjects) if subjects.any?
  if ARGV.include?("--auto") || (!$stdin.tty? && ARGV.include?("--from-replicate"))
    input = auto_mode
  elsif ARGV.include?("--from-replicate") && REPLICATE_PRESENT
    check_replicate
    return
  else
    input = get_input
  end

  return unless input

  patterns, variations, config = input

  files = patterns.flat_map { |pattern| Dir.glob(pattern) }
                  .reject { |f| File.basename(f).match?(/processed|masterpiece/) }

  if files.empty?
    $cli_logger.error "No files matched patterns!"
    return
  end

  $cli_logger.info "Processing #{files.count} files..."
  total_processed = 0
  total_variations = 0
  start_time = Time.now

  files.each_with_index do |file, i|
    begin
      $cli_logger.info "#{i + 1}/#{files.count}: #{File.basename(file)}"

      count = case config[:type]
              when :preset
                process_file(file, variations, config[:preset])
              when :random
                process_file(file, variations, nil, random_chain)
              when :recipe
                process_file(file, variations, nil, config[:recipe])
              else
                0
              end

      total_processed += 1 if count > 0
      total_variations += count
      GC.start if (i % 10).zero?

    rescue StandardError => e
      $logger.error "Failed #{file}: #{e.message}"
      $cli_logger.error "Error: #{File.basename(file)}"
    end
  end

  duration = (Time.now - start_time).round(2)
  $cli_logger.info "Complete! #{total_processed} files → #{total_variations} masterpieces (#{duration}s)"

  return unless REPLICATE_PRESENT && total_variations > 0
    $cli_logger.info "Tip: Run 'ruby replicate.rb' to generate more content!"

end
