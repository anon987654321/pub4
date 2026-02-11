#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing the expanded media production capabilities
require_relative '../lib/replicate'

puts "=" * 60
puts "MASTER2 Replicate - Full Media Production Engine Demo"
puts "=" * 60
puts

# Check if API key is available
if MASTER::Replicate.available?
  puts "✓ REPLICATE_API_KEY is configured"
else
  puts "⚠ REPLICATE_API_KEY not set (demo mode - showing available features)"
end

puts "\n" + "=" * 60
puts "Available Models by Category"
puts "=" * 60

categories = {
  "Image Generation" => [:flux, :flux_pro, :flux_kontext, :flux2, :sdxl, :kandinsky],
  "Video Generation" => [:hailuo, :mochi],
  "Music/Audio" => [:musicgen, :bark, :stable_audio],
  "3D Generation" => [:triposr, :trellis],
  "Upscale/Post-processing" => [:esrgan, :gfpgan],
  "Caption/Description" => [:blip]
}

categories.each do |category, models|
  puts "\n#{category}:"
  models.each do |model|
    model_id = MASTER::Replicate::MODELS[model]
    puts "  • #{model.to_s.ljust(15)} → #{model_id}"
  end
end

puts "\n" + "=" * 60
puts "New Convenience Methods"
puts "=" * 60

methods_desc = {
  generate_video: "Generate video from text prompt (Hailuo 2.3, Mochi)",
  generate_music: "Generate music from text description (MusicGen)",
  text_to_speech: "Convert text to natural speech (Bark TTS)",
  generate_3d: "Create 3D models from images (TripoSR, GLB format)",
  edit_image: "Text-guided image editing (Flux Kontext)",
  restore_face: "Enhance and restore faces (GFPGAN)"
}

methods_desc.each do |method, desc|
  puts "\n#{method}():"
  puts "  #{desc}"
end

puts "\n" + "=" * 60
puts "Example Usage"
puts "=" * 60

puts <<~EXAMPLES

  # Generate a cinematic video
  result = MASTER::Replicate.generate_video(
    prompt: "A majestic dragon flying over mountains at sunset",
    model: :hailuo,
    params: { duration: 5 }
  )

  # Generate background music
  result = MASTER::Replicate.generate_music(
    prompt: "Epic orchestral soundtrack, cinematic, dramatic",
    duration: 30
  )

  # Convert text to speech
  result = MASTER::Replicate.text_to_speech(
    text: "Welcome to the future of AI media production",
    voice: "v2/en_speaker_6"
  )

  # Generate 3D model from an image
  result = MASTER::Replicate.generate_3d(
    image_url: "https://example.com/photo.jpg",
    model: :triposr
  )

  # Edit an image with text guidance
  result = MASTER::Replicate.edit_image(
    image_url: "https://example.com/photo.jpg",
    prompt: "add cherry blossoms and golden hour lighting"
  )

  # Restore and enhance faces
  result = MASTER::Replicate.restore_face(
    image_url: "https://example.com/portrait.jpg"
  )

EXAMPLES

puts "=" * 60
puts "Backward Compatibility"
puts "=" * 60

puts <<~COMPAT

  All existing methods remain unchanged:
  • generate() - Image generation (now with more models)
  • upscale() - Image upscaling (Real-ESRGAN)
  • describe() - Image captioning (BLIP)
  • run() - Generic model runner
  • download_file() - File download utility

  The :flux alias still works for backward compatibility:
  MASTER::Replicate.generate(prompt: "...", model: :flux)
  
COMPAT

puts "=" * 60
puts "Integration with Cinematic & RepligenBridge"
puts "=" * 60

puts <<~INTEGRATION

  The new models coordinate with existing modules:
  
  • Cinematic.rb can now use video models for pipelines
  • RepligenBridge.rb WILD_CHAIN includes these models
  • Face restoration integrates with enhancement pipelines
  • 3D generation enables new creative workflows

INTEGRATION

puts "Demo complete!"
