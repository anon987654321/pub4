#!/usr/bin/env ruby
# frozen_string_literal: true

# Sherpa-ONNX + Kokoro Model Installer for Windows
# Downloads and sets up sherpa-onnx with Kokoro TTS models

require "net/http"
require "fileutils"

require "tempfile"

VERSION = "1.12.14"
TTS_DIR = File.expand_path(__dir__)

SHERPA_DIR = File.join(TTS_DIR, "sherpa-onnx")

# URLs for sherpa-onnx Windows binaries and Kokoro models
URLS = {

  sherpa_win64: "https://github.com/k2-fsa/sherpa-onnx/releases/download/v#{VERSION}/sherpa-onnx-v#{VERSION}-win-x64.zip",

  kokoro_model: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-v0_19.tar.bz2"

}.freeze

puts "Sherpa-ONNX + Kokoro Installer v#{VERSION}"
puts "=" * 50

puts

# ============================================================================
# DOWNLOAD HELPER

# ============================================================================

def download_file(url, destination, description)
  puts "📥 Downloading #{description}..."

  puts "    From: #{url}"

  puts "    To: #{destination}"

  uri = URI(url)
  redirect_limit = 5

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    request = Net::HTTP::Get.new(uri)

    http.request(request) do |response|
      # Handle redirects

      while [301, 302, 303, 307, 308].include?(response.code.to_i) && redirect_limit > 0

        location = response["location"]

        puts "    → Redirecting to: #{location}"

        uri = URI(location)

        redirect_limit -= 1

        http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
        request = Net::HTTP::Get.new(uri)

        response = http.request(request)

      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "Download failed: #{response.code} - #{response.message}"

      end

      total_size = response["content-length"].to_i
      downloaded = 0

      File.open(destination, "wb") do |file|
        response.read_body do |chunk|

          file.write(chunk)

          downloaded += chunk.bytesize

          if total_size > 0
            percent = (downloaded.to_f / total_size * 100).round(1)

            print "\r    Progress: #{percent}% (#{downloaded / 1024 / 1024}MB / #{total_size / 1024 / 1024}MB)"

          else

            print "\r    Downloaded: #{downloaded / 1024 / 1024}MB"

          end

        end

      end

      puts "\n    ✓ Complete"
    end

  end

rescue => e

  warn "\n    ✗ Failed: #{e.message}"

  raise

end

# ============================================================================
# EXTRACTION HELPERS

# ============================================================================

def extract_zip(zip_file, destination)
  puts "📦 Extracting ZIP archive..."

  # Use PowerShell to extract (built-in on Windows)
  cmd = [

    "powershell.exe",

    "-NoProfile",

    "-Command",

    "Expand-Archive",

    "-Path", "\"#{zip_file}\"",

    "-DestinationPath", "\"#{destination}\"",

    "-Force"

  ].join(" ")

  success = system(cmd)
  unless success
    raise "Failed to extract ZIP file"

  end

  puts "    ✓ Extracted to: #{destination}"
end

def extract_tar_bz2(tar_file, destination)
  puts "📦 Extracting TAR.BZ2 archive..."

  # Try to use tar.exe (Windows 10+ has built-in tar)
  if system("where tar.exe >nul 2>&1")

    cmd = "tar -xjf \"#{tar_file}\" -C \"#{destination}\""

    success = system(cmd)

    unless success
      raise "Failed to extract TAR.BZ2 file"

    end

  else

    # Fallback: extract manually with Ruby

    warn "    ⚠ tar.exe not found, attempting manual extraction..."

    require "zlib"

    # This is a simplified extraction - may not work for all tar.bz2 files
    # Recommend installing tar.exe or 7-Zip

    raise "Cannot extract TAR.BZ2 without tar.exe. Please install Git for Windows or 7-Zip."

  end

  puts "    ✓ Extracted to: #{destination}"
end

# ============================================================================
# INSTALLATION

# ============================================================================

def install_sherpa_onnx
  puts "\n[1/2] Installing Sherpa-ONNX Windows Binaries"

  puts "-" * 50

  if File.exist?(File.join(SHERPA_DIR, "bin", "sherpa-onnx-offline-tts.exe"))
    puts "    ✓ Sherpa-ONNX already installed"

    return

  end

  FileUtils.mkdir_p(SHERPA_DIR)
  temp_zip = Tempfile.new(["sherpa-onnx", ".zip"])
  download_file(URLS[:sherpa_win64], temp_zip.path, "Sherpa-ONNX Windows binaries")

  extract_zip(temp_zip.path, SHERPA_DIR)
  # The ZIP extracts to a versioned folder, move contents up
  extracted_dir = Dir.glob(File.join(SHERPA_DIR, "sherpa-onnx-v*")).first

  if extracted_dir

    Dir.glob(File.join(extracted_dir, "*")).each do |item|

      FileUtils.mv(item, SHERPA_DIR)

    end

    FileUtils.rm_rf(extracted_dir)

  end

  temp_zip.close
  temp_zip.unlink

  puts "    ✓ Sherpa-ONNX installed successfully"
end

def install_kokoro_model
  puts "\n[2/2] Installing Kokoro TTS Model"

  puts "-" * 50

  model_dir = File.join(SHERPA_DIR, "models", "kokoro")
  if File.exist?(File.join(model_dir, "kokoro-v0_19.onnx"))
    puts "    ✓ Kokoro model already installed"

    return

  end

  FileUtils.mkdir_p(model_dir)
  temp_tar = Tempfile.new(["kokoro", ".tar.bz2"])
  download_file(URLS[:kokoro_model], temp_tar.path, "Kokoro TTS model")

  extract_tar_bz2(temp_tar.path, model_dir)
  # Move files from extracted subdirectory if needed
  extracted_dir = Dir.glob(File.join(model_dir, "kokoro-*")).first

  if extracted_dir && File.directory?(extracted_dir)

    Dir.glob(File.join(extracted_dir, "*")).each do |item|

      FileUtils.mv(item, model_dir)

    end

    FileUtils.rm_rf(extracted_dir)

  end

  temp_tar.close
  temp_tar.unlink

  puts "    ✓ Kokoro model installed successfully"
end

# ============================================================================
# VERIFICATION

# ============================================================================

def verify_installation
  puts "\n✓ Installation Complete!"

  puts "=" * 50

  sherpa_exe = File.join(SHERPA_DIR, "bin", "sherpa-onnx-offline-tts.exe")
  model_file = File.join(SHERPA_DIR, "models", "kokoro", "kokoro-v0_19.onnx")

  if File.exist?(sherpa_exe)
    puts "✓ Sherpa-ONNX executable: #{sherpa_exe}"

  else

    warn "✗ Sherpa-ONNX executable not found"

  end

  if File.exist?(model_file)
    puts "✓ Kokoro model: #{model_file}"

  else

    warn "✗ Kokoro model not found"

  end

  puts "\nNext steps:"
  puts "  ruby claude_speak.rb \"Hello world\""

  puts "  ruby claude_speak.rb --list-voices"

  puts

end

# ============================================================================
# MAIN

# ============================================================================

begin
  install_sherpa_onnx

  install_kokoro_model

  verify_installation

rescue => e

  warn "\n\n✗ Installation failed: #{e.message}"

  warn e.backtrace.first(5).join("\n") if ENV["DEBUG"]

  exit 1

end

