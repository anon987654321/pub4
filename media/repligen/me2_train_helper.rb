#!/usr/bin/env ruby
# frozen_string_literal: true
# ME2 LoRA Training - Web Upload Helper

require "net/http"
require "json"

TOKEN = "r8_Oru5iWfF9T8jy0iw9FFFuzQHFJiDMNz03ZcHi"
ZIP_PATH = File.expand_path("__lora/me2_training.zip", __dir__)

puts "\n" + "=" * 70
puts "  🎨 ME2 LoRA TRAINING HELPER 🎨"
puts "=" * 70

puts "\n📦 Training package ready:"
puts "   Location: #{ZIP_PATH}"
puts "   Size: #{File.size(ZIP_PATH) / 1024}KB"
puts "   Images: 15"
puts "   Trigger word: ME2"

puts "\n🚀 TO TRAIN YOUR ME2 LoRA:"
puts "\n1. Go to: https://replicate.com/ostris/flux-dev-lora-trainer/train"
puts "\n2. Upload settings:"
puts "   - Click 'Choose file' and select: #{ZIP_PATH}"
puts "   - OR upload via file.io:"

# Upload to file.io for easy access
puts "\n   Uploading to file.io for easy download link..."
uri = URI("https://file.io")
req = Net::HTTP::Post.new(uri)
req.set_form([["file", File.read(ZIP_PATH), { filename: "me2_training.zip" }]], "multipart/form-data")

begin
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  data = JSON.parse(res.body)
  
  if data["success"]
    puts "\n   ✓ Temporary download link (expires in 14 days):"
    puts "     #{data["link"]}"
    puts "\n   Use this URL in Replicate's 'input_images' field"
  end
rescue => e
  puts "   (file.io upload failed: #{e.message})"
end

puts "\n3. Training parameters:"
puts "   trigger_word: ME2"
puts "   steps: 1500"
puts "   lora_rank: 16"
puts "   learning_rate: 0.0004"
puts "   resolution: 512,768,1024"
puts "   autocaption: true"
puts "   autocaption_prefix: ME2 person,"

puts "\n4. Click 'Create training'"
puts "\n5. Wait 15-30 minutes (~$10 cost)"

puts "\n6. Once complete, your model will be at:"
puts "   https://replicate.com/[your-username]/me2-lora"

puts "\n7. Use ME2 in prompts:"
puts '   ruby me2_catwalk.rb full'
puts '   (Update the script to use your trained LoRA)'

puts "\n" + "=" * 70
puts "Training zip is ready to upload!"
puts "=" * 70
