#!/usr/bin/env ruby
# frozen_string_literal: true

# Piper TTS Installer for Windows
# Downloads and configures Piper with ONNX models for offline, high-quality TTS

require "fileutils"
require "net/http"

require "uri"

require "json"

PIPER_DIR = "G:/pub/tts/piper"
PIPER_VERSION = "1.2.0"

PIPER_URL = "https://github.com/rhasspy/piper/releases/download/v#{PIPER_VERSION}/piper_windows_amd64.zip"

# High-quality voices
VOICES = {

  "en_US-lessac-medium" => "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx",

  "en_GB-alba-medium" => "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/alba/medium/en_GB-alba-medium.onnx"

}

def download_file(url, dest)
  puts "📥 Downloading: #{File.basename(dest)}"

  uri = URI(url)

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    request = Net::HTTP::Get.new(uri)

    http.request(request) do |response|

      File.open(dest, "wb") do |file|

        response.read_body do |chunk|

          file.write(chunk)

        end

      end

    end

  end

  puts "   ✓ Downloaded: #{File.basename(dest)}"
end

def install_piper
  puts "🎙️  Installing Piper TTS v#{PIPER_VERSION}\n\n"

  FileUtils.mkdir_p(PIPER_DIR)
  FileUtils.mkdir_p("#{PIPER_DIR}/models")

  # Download Piper executable
  zip_file = "#{PIPER_DIR}/piper.zip"

  unless File.exist?("#{PIPER_DIR}/piper.exe")

    download_file(PIPER_URL, zip_file)

    puts "📦 Extracting Piper..."
    system("powershell -Command \"Expand-Archive -Path '#{zip_file}' -DestinationPath '#{PIPER_DIR}' -Force\"")

    # Move files from extracted subdirectory
    Dir.glob("#{PIPER_DIR}/piper_windows_amd64/*").each do |file|

      FileUtils.mv(file, PIPER_DIR, force: true)

    end

    FileUtils.rm_rf("#{PIPER_DIR}/piper_windows_amd64")
    File.delete(zip_file)

    puts "   ✓ Piper installed"

  else

    puts "✓ Piper already installed"

  end

  # Download voice models
  VOICES.each do |name, url|

    model_file = "#{PIPER_DIR}/models/#{name}.onnx"

    json_file = "#{PIPER_DIR}/models/#{name}.onnx.json"

    unless File.exist?(model_file)
      download_file(url, model_file)

      download_file("#{url}.json", json_file)

    else

      puts "✓ Voice already installed: #{name}"

    end

  end

  puts "\n✅ Piper TTS installation complete!"
  puts "\nTest with:"

  puts "  ruby G:/pub/tts/smart_say.rb \"Hello world\""

end

begin
  install_piper

rescue Interrupt

  puts "\n\n✋ Installation cancelled"

  exit 1

rescue => e

  warn "\n❌ Installation failed: #{e.message}"

  warn e.backtrace.first(3).join("\n")

  exit 1

end

