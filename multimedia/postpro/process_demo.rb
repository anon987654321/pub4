require "logger"
require "json"
require "time"
require "fileutils"

require_relative "__shared/@bootstrap"
require_relative "__shared/@fx_core"
require_relative "__shared/@fx_creative"

BOOTSTRAP = PostproBootstrap.run
$logger = Logger.new("postpro.log", "daily", level: Logger::DEBUG)
$cli_logger = Logger.new(STDOUT, level: Logger::INFO)

if BOOTSTRAP[:gems][:vips]
  require "vips"
end

CAMERA_PROFILES = BOOTSTRAP[:camera_profiles]
CONFIG = BOOTSTRAP[:config]

if BOOTSTRAP[:gems][:vips]
  input_file = ARGV[0] || "../before.jpg"
  
  # Load and process
  image = load_image(input_file)
  if image
    $cli_logger.info "Processing with Portrait preset (Kodak Portra)..."
    processed = preset(image, :portrait)
    
    if processed
      output_file = input_file.sub(File.extname(input_file), "_portrait#{File.extname(input_file)}")
      processed.write_to_file(output_file, Q: 95)
      $cli_logger.info "✓ Saved: #{File.basename(output_file)}"
    else
      $cli_logger.error "✗ Processing failed"
    end
  else
    $cli_logger.error "✗ Could not load image"
  end
else
  $cli_logger.error "✗ libvips not available"
  puts "\nInstall libvips: apt-cyg install vips (or brew install vips on macOS)"
end
