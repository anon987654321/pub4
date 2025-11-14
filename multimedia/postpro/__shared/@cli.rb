# frozen_string_literal: true

REPLIGEN_PRESENT = File.exist?("repligen.rb")

def show_postpro_banner
  $cli_logger.info <<~BANNER

    ╔═══════════════════════════════════════════════════════════╗
    ║            POSTPRO v14.2.0 Professional Edition          ║
    ║         Advanced Color Science & Cinematic Workflows     ║
    ╚═══════════════════════════════════════════════════════════╝

    Film Stocks: Kodak Portra, Vision3, Fuji Velvia, Tri-X
    Presets: Portrait, Landscape, Street, Blockbuster
    #{REPLIGEN_PRESENT ? "🔗 Repligen Integration Active" : ""}
  BANNER
end

def check_repligen
  return unless REPLIGEN_PRESENT
  $cli_logger.info 'Repligen detected! Auto-processing generated images...'
  recent_files = Dir.glob('*_generated_*.{jpg,jpeg,png,webp}')
                    .select { |f| File.mtime(f) > (Time.now - 300) }
  if recent_files.any?
    $cli_logger.info "Found #{recent_files.count} recent Repligen outputs"
    preset_name = PROMPT.select('Choose preset for Repligen outputs:', PRESETS.keys)
    recent_files.each { |file| process_file(file, 2, preset_name) }
  end
end

def process_file(file, variations, preset_name = nil, recipe_data = nil, random_effects = nil, mode = "professional")
  image = load_image(file)
  return 0 unless image

  if CONFIG["apply_camera_profile_first"]
    profile = get_camera_profile(image)
    if profile
      image = apply_camera_profile(image, profile)
      PostproBootstrap.dmesg "applied camera profile for #{file}"
    end
  end

  processed_count = 0
  variations.times do |i|
    begin
      processed = if preset_name
                     preset(image, preset_name)
                   elsif recipe_data
                     recipe(image, recipe_data)
                   elsif random_effects
                     random_fx(image, random_effects, mode)
                   else
                     next
                   end

      next unless processed
      processed = rgb_bands(processed)
      timestamp = Time.now.strftime("%Y%m%d%H%M%S")
      suffix = preset_name || "processed"
      output = file.sub(File.extname(file), "_#{suffix}_v#{i + 1}_#{timestamp}#{File.extname(file)}")
      quality = CONFIG["jpeg_quality"] || 95
      processed.write_to_file(output, Q: quality)
      $cli_logger.info "Saved masterpiece #{i + 1}: #{File.basename(output)}"
      processed_count += 1
    rescue StandardError => e
      $logger.error "Variation #{i + 1} failed: #{e.message}"
    end
  end
  processed_count
end

def get_input
  show_postpro_banner
  check_repligen if REPLIGEN_PRESENT

  if PROMPT
    workflow = PROMPT.select("Choose workflow:", [
      "Masterpiece Presets (Recommended)",
      "Random Effects (Experimental)",
      "Custom JSON Recipe"
    ])

    patterns = PROMPT.ask("File patterns:", default: "**/*.{jpg,jpeg,png,webp}").strip.split(",").map(&:strip)
    variations = PROMPT.ask("Variations per image:", convert: :int, default: CONFIG["variations"] || 2) { |q| q.in("1-5") }

    case workflow
    when "Masterpiece Presets (Recommended)"
      preset_name = PROMPT.select("Choose preset:", PRESETS.keys)
      [patterns, variations, { type: :preset, preset: preset_name }]
    when "Random Effects (Experimental)"
      mode = PROMPT.select("Mode:", ["Professional", "Experimental"])
      fx_count = PROMPT.ask("Effects per variation:", convert: :int, default: 4) { |q| q.in("2-8") }
      [patterns, variations, { type: :random, mode: mode.downcase, fx: fx_count }]
    when "Custom JSON Recipe"
      file = PROMPT.ask("Recipe file path:").strip
      recipe_data = File.exist?(file) ? JSON.parse(File.read(file)) : {}
      [patterns, variations, { type: :recipe, recipe: recipe_data }]
    end
  else
    get_input_simple
  end
end

def get_input_simple
  puts "\n🎬 Workflow Selection:"
  puts "  1. Masterpiece Presets (Recommended)"
  puts "  2. Random Effects (Experimental)"
  puts "  3. Custom JSON Recipe"
  print "\nChoose workflow [1]: "
  workflow_choice = gets&.chomp&.strip
  workflow_choice = "1" if workflow_choice.empty?

  print "File patterns [**/*.{jpg,jpeg,png,webp}]: "
  patterns_input = gets&.chomp&.strip
  patterns = patterns_input.empty? ? ["**/*.{jpg,jpeg,png,webp}"] : patterns_input.split(",").map(&:strip)

  default_variations = CONFIG["variations"] || 2
  print "Variations per image [#{default_variations}]: "
  variations_input = gets&.chomp&.strip
  variations = variations_input.empty? ? default_variations : variations_input.to_i

  case workflow_choice
  when "1"
    puts "\n🎨 Available Presets:"
    PRESETS.keys.each_with_index { |preset, i| puts "  #{i+1}. #{preset}" }
    default_preset = CONFIG["default_preset"] || "portrait"
    print "\nChoose preset [#{default_preset}]: "
    preset_input = gets&.chomp&.strip
    preset_name = if preset_input.empty?
                    default_preset.to_sym
                  elsif preset_input.to_i > 0 && preset_input.to_i <= PRESETS.keys.size
                    PRESETS.keys[preset_input.to_i - 1]
                  else
                    preset_input.to_sym
                  end
    [patterns, variations, { type: :preset, preset: preset_name }]
  when "2"
    print "Mode (professional/experimental) [professional]: "
    mode_input = gets&.chomp&.strip
    mode = mode_input.empty? ? "professional" : mode_input.downcase
    print "Effects per variation [4]: "
    fx_input = gets&.chomp&.strip
    fx_count = fx_input.empty? ? 4 : fx_input.to_i
    [patterns, variations, { type: :random, mode: mode, fx: fx_count }]
  when "3"
    print "Recipe file path: "
    file = gets&.chomp&.strip
    recipe_data = File.exist?(file) ? JSON.parse(File.read(file)) : {}
    [patterns, variations, { type: :recipe, recipe: recipe_data }]
  else
    [patterns, variations, { type: :preset, preset: :portrait }]
  end
end

def auto_mode
  PostproBootstrap.dmesg "auto mode enabled"
  patterns = ["**/*.{jpg,jpeg,png,webp}"]
  variations = CONFIG["variations"] || 2
  preset_name = CONFIG["default_preset"] || "portrait"
  [patterns, variations, { type: :preset, preset: preset_name }]
end

def auto_launch
  if ARGV.include?("--auto") || (!$stdin.tty? && ARGV.include?("--from-repligen"))
    input = auto_mode
  elsif ARGV.include?("--from-repligen") && REPLIGEN_PRESENT
    check_repligen
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
                fx = %w[grain leaks sepia bloom teal_orange cross vhs chroma glitch flare]
                selected = config[:mode] == "experimental" ? fx : fx.first(6)
                random_effects = selected.shuffle.take(config[:fx])
                process_file(file, variations, nil, nil, random_effects, config[:mode])
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

  if REPLIGEN_PRESENT && total_variations > 0
    $cli_logger.info "Tip: Run 'ruby repligen.rb' to generate more content!"
  end
end
