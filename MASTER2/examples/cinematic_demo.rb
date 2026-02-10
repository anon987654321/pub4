#!/usr/bin/env ruby
# frozen_string_literal: true

# Cinematic Pipeline Demo
# Demonstrates the Cinematic AI Pipeline capabilities

require_relative '../lib/master'

puts "=" * 60
puts "MASTER2 Cinematic AI Pipeline Demo"
puts "=" * 60
puts

# Test 1: List presets
puts "1. Listing available presets..."
result = MASTER::Cinematic.list_presets
if result.ok?
  puts "   ✓ Found #{result.value[:presets].size} presets"
  result.value[:presets].first(3).each do |preset|
    puts "     - #{preset[:name]} (#{preset[:source]})"
  end
else
  puts "   ✗ Failed: #{result.error}"
end
puts

# Test 2: Create a pipeline
puts "2. Creating a custom pipeline..."
pipeline = MASTER::Cinematic::Pipeline.new
pipeline.chain('stability-ai/sdxl', { 
  prompt: 'cinematic movie scene, dramatic lighting',
  guidance_scale: 10.0 
})
puts "   ✓ Pipeline created with #{pipeline.stages.size} stage(s)"
puts

# Test 3: Save pipeline
puts "3. Saving pipeline as preset..."
result = pipeline.save_preset(
  name: 'demo-pipeline',
  description: 'Demo pipeline for testing',
  tags: ['demo', 'test']
)
if result.ok?
  puts "   ✓ Saved to: #{result.value[:path]}"
else
  puts "   ✗ Failed: #{result.error}"
end
puts

# Test 4: Load pipeline
puts "4. Loading saved pipeline..."
result = MASTER::Cinematic::Pipeline.load('demo-pipeline')
if result.ok?
  loaded_pipeline = result.value
  puts "   ✓ Loaded pipeline with #{loaded_pipeline.stages.size} stage(s)"
else
  puts "   ✗ Failed: #{result.error}"
end
puts

# Test 5: Generate random pipeline
puts "5. Generating random pipeline..."
result = MASTER::Cinematic::Pipeline.random(length: 3, category: :image)
if result.ok?
  random_pipeline = result.value
  puts "   ✓ Generated pipeline with #{random_pipeline.stages.size} stages:"
  random_pipeline.stages.each_with_index do |stage, i|
    puts "     #{i+1}. #{stage[:model]}"
  end
else
  puts "   ✗ Failed: #{result.error}"
end
puts

# Test 6: Check built-in presets
puts "6. Checking built-in presets..."
MASTER::Cinematic::PRESETS.each do |name, preset|
  puts "   - #{name}: #{preset[:models].size} models"
end
puts

puts "=" * 60
puts "Demo complete!"
puts
puts "To use the pipeline with actual images, ensure you have:"
puts "  - REPLICATE_API_KEY environment variable set"
puts "  - Input image file"
puts
puts "Example usage:"
puts "  result = MASTER::Cinematic.apply_preset('photo.jpg', 'blade-runner')"
puts "  puts result.value[:final]"
puts "=" * 60
