# frozen_string_literal: true

def run_one_shot
  input_path = argv_flag("--input")
  output_path = argv_flag("--output")
  preset_name = argv_flag("--preset").to_sym

  unless File.exist?(input_path)
    $cli_logger.error "Input not found: #{input_path}"
    exit 1
  end
  unless PRESETS.key?(preset_name)
    $cli_logger.error "Unknown preset: #{preset_name}. Valid: #{PRESETS.keys.join(", ")}"
    exit 1
  end

  if ARGV.include?("--tiff16")
    output_path = output_path.sub(/\.(jpg|jpeg|png|webp)$/i, ".tif")
  end
  Postpro::Constitution.verify_distinct_source!(input_path:, output_path:)

  image = load_image(input_path)
  unless image
    $cli_logger.error "Failed to load: #{input_path}"
    exit 1
  end
  # Every render path starts from the camera-corrected negative. Generated
  # images without EXIF pass through unchanged; photographed sources do not
  # depend on which entry point happened to grade them.
  image = camera_corrected(image, input_path)

  processed = preset(image, preset_name)
  # Operator, 2026-08-12: the four entry points now grain identically. This one
  # and run_watch did not, so the same --preset gave a different negative
  # depending on whether it arrived through a batch or through replicate's
  # --postpro handoff -- and the handoff is the path that produces the finals.
  processed = apply_finishing_grain(anchor_tones(processed), preset_name)
  processed = rgb_bands(processed)
  quality = CONFIG["jpeg_quality"] || 95
  # process_file honours --tiff16 and this ignored it, so the one-shot mode
  # -- the mode replicate's --postpro handoff uses, and the only one with an
  # explicit output path -- quietly wrote 8-bit JPEG when asked for 16-bit TIFF.
  # A grading tool silently halving its bit depth is the kind of thing you find
  # much later, in the file.
  if ARGV.include?("--tiff16") || output_path.end_with?(".tif", ".tiff")
    output_path = output_path.sub(/\.(jpg|jpeg|png|webp)$/i, ".tif")
    processed.cast("ushort").write_to_file(output_path)
  else
    processed.write_to_file(output_path, Q: quality)
  end
  write_comparison(image, processed, output_path)
  sidecar = write_grade_sidecar(input_path, output_path, preset_name, image, processed)
  sidecar[:quality][:warnings].each { |warning| $cli_logger.info "warn #{warning}" }
  $cli_logger.info "ok preset=#{preset_name} out=#{output_path}"
end

def watch_mode?
  ARGV.include?("--watch")
end

# One frame through one preset on every stock, tiled in STOCKS order with each
# stock's name under its tile.
#
# The eye compares neighbours without moving between windows, and the
# difference between two emulsions is only visible side by side. Graded at
# STOCK_SHEET_CELL rather than at full size: fourteen full grades of a large
# frame take minutes, and grain is sized by image width, so a tile carries the
# grain a print of that size would.
STOCK_SHEET_CELL = 512
STOCK_SHEET_GAP = 12
STOCK_SHEET_LABEL = 22

def stock_sheet_label(stock, cell:)
  label = Vips::Image.text(stock.to_s, dpi: 62)
  label_height = STOCK_SHEET_LABEL - 4
  scale = [cell.to_f / label.width, label_height.to_f / label.height, 1.0].min
  label = label.resize(scale) if scale < 1.0
  label.ifthenelse([210, 210, 210], [18, 18, 18], blend: true)
end

def stock_sheet(image, preset_name, cell: STOCK_SHEET_CELL)
  small = rgb_bands(image.thumbnail_image(cell, height: cell, size: :down))
  stocks = STOCKS.keys
  tiles = stocks.map do |stock|
    graded = rgb_bands(apply_finishing_grain(preset(small, preset_name, stock: stock), preset_name))
    tag = stock_sheet_label(stock, cell:)
    tile = (Vips::Image.black(cell, cell + STOCK_SHEET_LABEL) + 18).cast(:uchar).bandjoin([18, 18])
    label_x = (cell - tag.width) / 2
    label_y = cell + 4 + ((STOCK_SHEET_LABEL - 4 - tag.height) / 2)
    tile.insert(graded.cast(:uchar), (cell - graded.width) / 2, (cell - graded.height) / 2)
        .insert(tag, label_x, label_y)
  end
  columns = Math.sqrt(stocks.length).ceil
  [Vips::Image.arrayjoin(tiles, across: columns, shim: STOCK_SHEET_GAP, background: [18, 18, 18]), stocks]
end

def run_stock_sheet
  input_path = argv_flag("--stock-sheet")
  preset_name = (argv_flag("--preset") || "house").to_sym
  abort "postpro: --stock-sheet needs a readable file" unless input_path && File.file?(input_path)
  abort "postpro: unknown preset #{preset_name}" unless PRESETS.key?(preset_name)

  ext = File.extname(input_path)
  requested_output = argv_flag("--output")
  output = requested_output
  if output.to_s.empty?
    safe_stem = File.basename(input_path, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
    output = File.join(Postpro::Constitution.output_dir_for(input_path), "postpro_#{safe_stem}_stocks_#{preset_name}.jpg")
    output = Postpro::Constitution.available_output_path(output)
    Postpro::Constitution.verify_output!(input_path: input_path, output_path: output)
  else
    Postpro::Constitution.verify_distinct_source!(input_path:, output_path: output)
  end
  image = load_image(input_path)
  abort "postpro: could not load #{input_path}" unless image

  sheet, stocks = stock_sheet(camera_corrected(image, input_path), preset_name)
  sheet.write_to_file(output, Q: CONFIG["jpeg_quality"] || 95)
  $cli_logger.info "ok stock sheet preset=#{preset_name} stocks=#{stocks.length} out=#{output}"
end

def random_mode?
  ARGV.include?("--random")
end

# A bare path names the subject: `postpro.rb photo.png` grades that one
# photograph, `postpro.rb ~/Pictures` a few random picks from the folder. Flag
# values are not paths (`--count 3` is not a file called 3), so every
# value-taking flag's token is set aside before the hunt.
VALUE_FLAGS = %w[
  --input --output --preset --reference --count -n --watch --describe-preset
  --css-filter --export-lut --size --stock-sheet --random --rescue --measure
  --against --set --fit-grain --quality
].freeze

# Every bare path on the line is a subject, so `postpro.rb a.jpg b.jpg c.jpg`
# grades all three; it used to grade the first and drop the rest in silence.
# `uplift` is a mode word for --random, not a path.
def positional_subjects
  flag_values = VALUE_FLAGS.filter_map { |flag| argv_flag(flag) }
  ARGV.reject { |token| token.start_with?("-") || flag_values.include?(token) || token == "uplift" }
end

def positional_subject = positional_subjects.first

# --random names its subjects either as its own value (`--random photo.jpg`) or
# as bare paths anywhere else on the line. Without this, `--random --count 10
# photo.jpg` ignored the photograph and graded whatever sat in ~/Downloads.
def random_subjects
  named = argv_flag("--random")
  named = nil if named.nil? || named.start_with?("-") || named == "uplift" || !File.exist?(named)
  ([named] + positional_subjects).compact.uniq
end

# A batch is refused whole, before anything renders, when one of its paths is
# neither an image nor a folder: a typo at the end of the line must not cost
# the renders at the start of it a half-finished run.
def refuse_bad_subjects!(subjects)
  subjects.each do |subject|
    problem = subject_problem(subject)
    next unless problem

    $cli_logger.error "#{problem}: #{subject}"
    exit 1
  end
end

def subject_problem(subject)
  return "No such file or directory" unless File.exist?(subject)

  "Not an image" if File.file?(subject) && !subject.match?(/\.(jpe?g|png|webp)\z/i)
end

def run_random_subjects(subjects)
  return run_random if subjects.empty?

  refuse_bad_subjects!(subjects)
  subjects.each { |subject| run_random(subject) }
end

# Resolve the best available downloads directory on Android/Termux or desktop.
def downloads_dir
  candidates = [
    argv_flag("--random"),
    File.expand_path("~/storage/downloads"),
    "/sdcard/Download",
    File.expand_path("~/Downloads"),
    Dir.pwd,
  ]
  candidates.compact.find { |d| File.directory?(d) }
end

# --random [DIR] [uplift] [--count N], or a bare positional IMAGE | DIR
#
# Five to ten pictures per photograph (five in heavy mode, or exactly --count),
# each through its own chain, numbered in the order they were drawn and written
# beside the photograph they came from.
#
# The default used to be a pair of stacked presets applied to every image in
# the folder, which for a folder of two hundred is a long afternoon and two
# hundred near neighbours. A run is now a handful of genuinely different
# attempts, which is what random is for. `uplift` still stacks presets.
def run_random(subject = nil)
  dir = subject || downloads_dir

  files =
    if subject && File.file?(subject)
      [subject]
    else
      Dir.glob(File.join(dir, "**", "*.{jpg,jpeg,JPG,JPEG,png,PNG,webp,WEBP}"))
         .reject { |f| File.basename(f).match?(/processed|masterpiece|postpro|_v\d+_/) }
    end

  if files.empty?
    $cli_logger.error "No images in #{dir}"
    return
  end

  return run_uplift(dir, files) if ARGV.include?("uplift")

  # A fresh seed per run unless one was asked for, because the point of a random
  # run is that the next one differs. It is printed and written into every
  # sidecar, so POSTPRO_SEED=<that> renders the same variation family again.
  $postpro_seed = Random.new_seed % 2_147_483_647 unless ENV.key?("POSTPRO_SEED")
  rng = Random.new(postpro_seed)
  override = (argv_flag("--count") || argv_flag("-n"))&.to_i
  variations = override || RANDOM_TAKES
  PostproBootstrap.dmesg "random subject=#{subject || dir} pool=#{files.count} " \
                         "variations=#{variations} seed=#{$postpro_seed}"

  # A family of RANDOM_TAKES materially different attempts per image; --count
  # sets any other number. Heavy mode deals the lanes round-robin, so one run
  # always spans subtle analog to bleeding edge, and at ten it does so twice.
  files.each_with_index do |file, file_index|
    count = (override || RANDOM_TAKES).clamp(1, 24)

    Postpro::Constitution.verify_batch!(variation_count: count, explicit_count: !override.nil?)
    drawn = []
    looks = []
    Postpro::Constitution.retire_previous_renders!(file)
    count.times do |index|
      number = index + 1
      lane = heavy_mode? ? HEAVY_LANE_DEAL[index % HEAVY_LANE_DEAL.size] : nil

      attempts = 0
      refused = []
      begin
        look = heavy_mode? ? next_heavy_look(rng, looks + refused) : nil
        chain = look ? look_led_chain(rng, look:, avoid: drawn, lane:) : random_chain(rng, avoid: drawn, lane:)
        Postpro::Constitution.verify_chain!(chain: chain, stage_rank: random_stage_rank)
        drew = "#{File.basename(file)} — #{look} #{random_chain_name(chain)}"
        $cli_logger.info "#{file_index + 1}/#{files.count} #{number}/#{count}: #{drew}"

        take = RandomTake.new(number:, look:, lane: lane || random_chain_lane(chain))
        process_file(file, 1, nil, chain, take:)
        drawn << chain
        looks << look if look
      rescue RuntimeError => e
        # A take that destroyed the picture is drawn again, on another look.
        raise unless e.message.start_with?("all ") && (attempts += 1) < 4

        refused << look
        retry
      end
    rescue StandardError => e
      # One refused chain costs one take, not the rest of the family.
      failure = "take #{number} failed: #{e.message}"
      $logger.error "random #{File.basename(file)} #{failure}"
      $cli_logger.error failure
    end

    write_contact_sheet(file) if contact_sheet?
  rescue StandardError => e
    $logger.error "random #{File.basename(file)}: #{e.message}"
  end
end
