#!/usr/bin/env ruby
# frozen_string_literal: true
# Train ME2 LoRA on Replicate

require "net/http"
require "json"
require "base64"

TOKEN = "r8_Oru5iWfF9T8jy0iw9FFFuzQHFJiDMNz03ZcHi"
ZIP_PATH = "G:\\pub\\media\\repligen\\__lora\\me2_training.zip"

def api(path, body)
  uri = URI("https://api.replicate.com/v1#{path}")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Token #{TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = body.to_json
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
end

puts "\n" + "=" * 70
puts "  🎨 ME2 LoRA TRAINING - Starting on Replicate 🎨"
puts "=" * 70

# Step 1: Upload training zip
puts "\n📤 Step 1: Uploading training images (#{File.size(ZIP_PATH) / 1024}KB)..."

# Read and encode the zip file
zip_data = File.read(ZIP_PATH)
zip_base64 = Base64.strict_encode64(zip_data)
data_uri = "data:application/zip;base64,#{zip_base64}"

puts "✓ Training zip prepared"

# Step 2: Create training
puts "\n🚀 Step 2: Submitting LoRA training job..."
puts "   Trigger word: ME2"
puts "   Steps: 1500"
puts "   Learning rate: 0.0004"
puts "   Resolution: 512,768,1024"

# Get Replicate username first
uri = URI("https://api.replicate.com/v1/account")
req = Net::HTTP::Get.new(uri)
req["Authorization"] = "Token #{TOKEN}"
account_res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
username = JSON.parse(account_res.body)["username"] || "anon"

puts "   Username: #{username}"

res = api("/models/ostris/flux-dev-lora-trainer/versions/4ffd32160efd92e956d39c5338a9b8fbafca58e03f791f6d8011f3e20e8ea6fa/trainings", {
  destination: "#{username}/me2-lora",
  input: {
    input_images: data_uri,
    trigger_word: "ME2",
    steps: 1500,
    lora_rank: 16,
    optimizer: "adamw8bit",
    batch_size: 1,
    resolution: "512,768,1024",
    autocaption: true,
    autocaption_prefix: "ME2 person,",
    learning_rate: 0.0004,
    wandb_project: "me2_lora",
    wandb_save_interval: 100,
    caption_dropout_rate: 0.05,
    cache_latents_to_disk: false,
    wandb_sample_interval: 100
  }
})

result = JSON.parse(res.body)

if result["id"]
  puts "\n✓ Training started!"
  puts "=" * 70
  puts "Training ID: #{result["id"]}"
  puts "Status URL: https://replicate.com/p/#{result["id"]}"
  puts "\nThis will take 15-30 minutes and cost ~$10"
  puts "Check status at the URL above"
  puts "\nOnce complete, use with:"
  puts '  ruby repligen.rb generate "ME2 woman walking down catwalk, haute couture"'
  puts "=" * 70
else
  puts "\n✗ Training failed!"
  puts "Error: #{result["detail"] || result["error"] || "Unknown error"}"
  puts "\nFull response:"
  puts JSON.pretty_generate(result)
end
