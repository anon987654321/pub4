#!/usr/bin/env ruby
# frozen_string_literal: true
# ME2 LoRA - Automated Training via Replicate API

require "net/http"
require "json"

TOKEN = "r8_Oru5iWfF9T8jy0iw9FFFuzQHFJiDMNz03ZcHi"

def api(method, path, body = nil)
  uri = URI("https://api.replicate.com/v1#{path}")
  req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
  req["Authorization"] = "Token #{TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = body.to_json if body
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
end

puts "\n" + "=" * 70
puts "  🎨 ME2 LoRA AUTOMATED TRAINING 🎨"
puts "=" * 70

# Step 1: Upload to a temporary public URL
puts "\n📤 Step 1: Preparing training data..."

# For now, let's use the Replicate file upload endpoint
zip_path = File.expand_path("__lora/me2_training.zip", __dir__)
zip_size_mb = File.size(zip_path) / 1024.0 / 1024.0

puts "   Training zip: #{zip_size_mb.round(2)}MB"
puts "   Images: 15 photos of ME2"

# Try uploading via Replicate's file endpoint
puts "\n📤 Step 2: Uploading to Replicate..."

# Create file upload
upload_res = api(:post, "/files", {
  metadata: {
    purpose: "training"
  }
})

upload_data = JSON.parse(upload_res.body)

if upload_data["urls"] && upload_data["urls"]["upload"]
  upload_url = upload_data["urls"]["upload"]
  file_id = upload_data["id"]
  
  puts "   File ID: #{file_id}"
  puts "   Uploading..."
  
  # Upload the actual file
  uri = URI(upload_url)
  req = Net::HTTP::Put.new(uri)
  req.body = File.read(zip_path)
  req["Content-Type"] = "application/zip"
  
  upload_result = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end
  
  if upload_result.code.to_i == 200
    puts "   ✓ Upload complete!"
    
    # Step 3: Create training
    puts "\n🚀 Step 3: Starting LoRA training..."
    
    # First, create the destination model
    puts "   Creating model repository..."
    
    model_res = api(:post, "/models", {
      owner: "anon987654321",
      name: "me2-lora",
      visibility: "private",
      hardware: "gpu-a40-large",
      description: "ME2 LoRA - Custom trained model"
    })
    
    model_result = JSON.parse(model_res.body)
    
    if model_result["name"] || model_result["detail"]&.include?("already exists")
      puts "   ✓ Model ready"
      
      # Now create training
      training_res = api(:post, "/models/ostris/flux-dev-lora-trainer/versions/4ffd32160efd92e956d39c5338a9b8fbafca58e03f791f6d8011f3e20e8ea6fa/trainings", {
        destination: "anon987654321/me2-lora",
        input: {
          input_images: "https://replicate.delivery/files/#{file_id}",
          trigger_word: "ME2",
          steps: 1500,
          lora_rank: 16,
          optimizer: "adamw8bit",
          batch_size: 1,
          resolution: "512,768,1024",
          autocaption: true,
          autocaption_prefix: "ME2 person,",
          learning_rate: 0.0004
        }
      })
      
      training_result = JSON.parse(training_res.body)
      
      if training_result["id"]
        puts "\n✓ Training started!"
        puts "=" * 70
        puts "Training ID: #{training_result["id"]}"
        puts "Status: #{training_result["status"]}"
        puts "\nMonitor progress:"
        puts "https://replicate.com/p/#{training_result["id"]}"
        puts "\nEstimated time: 15-30 minutes"
        puts "Cost: ~$10"
        puts "\nOnce complete, your model will be at:"
        puts "https://replicate.com/anon987654321/me2-lora"
        puts "=" * 70
        
        # Save training ID
        File.write("me2_training_id.txt", training_result["id"])
        puts "\n✓ Training ID saved to: me2_training_id.txt"
      else
        puts "\n✗ Training failed!"
        puts JSON.pretty_generate(training_result)
      end
    else
      puts "\n✗ Model creation failed!"
      puts JSON.pretty_generate(model_result)
    end
  else
    puts "   ✗ Upload failed: #{upload_result.code}"
  end
else
  puts "\n✗ File upload initialization failed!"
  puts JSON.pretty_generate(upload_data)
end
