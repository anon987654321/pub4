#!/usr/bin/env ruby
# frozen_string_literal: true

require "sqlite3"
require "json"
require "fileutils"

# Chain Generator - Creates random model chains for motion graphics

class ChainGenerator
  CATEGORIES = {
    generators: ["image-generation", "video-generation", "text-to-video", "text-to-image"],
    effects: ["style-transfer", "image-to-image", "video-editing"],
    depth: ["depth-estimation", "3d-generation"],
    motion: ["video-interpolation", "motion-transfer", "animation"],
    audio: ["text-to-speech", "music-generation", "audio-reactive"],
    upscale: ["super-resolution", "upscaling", "restoration"],
    utility: ["background-removal", "segmentation", "object-detection"]
  }

  def initialize
    @db = SQLite3::Database.new("repligen_models.db")
  end

  def get_models_by_category(category)
    @db.execute(
      "SELECT id, description FROM models WHERE category = ? ORDER BY run_count DESC",
      [category]
    ).map { |row| { id: row[0], desc: row[1] } }
  end

  def generate_random_chain(length: 5, seed_category: nil)
    chain = []
    
    # Step 1: Start with a generator
    generators = get_models_by_category(seed_category || CATEGORIES[:generators].sample)
    return [] if generators.empty?
    
    chain << {
      step: 1,
      model: generators.sample[:id],
      purpose: "Generate initial content"
    }
    
    # Step 2-N: Add random effects
    (length - 2).times do |i|
      category_type = [:effects, :depth, :motion, :upscale].sample
      category = CATEGORIES[category_type].sample
      models = get_models_by_category(category)
      
      next if models.empty?
      
      chain << {
        step: i + 2,
        model: models.sample[:id],
        purpose: category_type.to_s.tr("_", " ").capitalize
      }
    end
    
    # Final step: Upscale or polish
    upscalers = get_models_by_category(CATEGORIES[:upscale].sample)
    unless upscalers.empty?
      chain << {
        step: length,
        model: upscalers.sample[:id],
        purpose: "Final upscale"
      }
    end
    
    chain
  end

  def generate_cinematic_chain
    [
      { step: 1, model: "anon987654321/ra2", purpose: "Portrait generation" },
      { step: 2, model: "depth-anything/v2", purpose: "Depth map" },
      { step: 3, model: "stabilityai/stable-video-diffusion", purpose: "Add motion" },
      { step: 4, model: "style-transfer-model", purpose: "Artistic style" },
      { step: 5, model: "topaz/video-enhance", purpose: "Upscale 4K" }
    ]
  end

  def generate_psychedelic_chain
    [
      { step: 1, model: "black-forest-labs/flux-2-pro", purpose: "Base image" },
      { step: 2, model: "deep-dream", purpose: "Psychedelic patterns" },
      { step: 3, model: "kaleidoscope-effect", purpose: "Kaleidoscope" },
      { step: 4, model: "color-shift", purpose: "Color manipulation" },
      { step: 5, model: "video-morph", purpose: "Fluid morphing" },
      { step: 6, model: "audio-reactive", purpose: "Music sync" }
    ]
  end

  def generate_glitch_art_chain
    [
      { step: 1, model: "flux-2-dev", purpose: "Quick generation" },
      { step: 2, model: "glitch-effect", purpose: "Digital corruption" },
      { step: 3, model: "pixel-sort", purpose: "Pixel sorting" },
      { step: 4, model: "rgb-split", purpose: "Chromatic aberration" },
      { step: 5, model: "noise-injection", purpose: "Analog noise" }
    ]
  end

  def display_chain(chain, title: "Generated Chain")
    puts "\n" + "="*70
    puts title.center(70)
    puts "="*70
    
    chain.each do |step|
      puts "\n#{step[:step]}. #{step[:model]}"
      puts "   → #{step[:purpose]}"
    end
    
    puts "\n" + "="*70
    puts "Total steps: #{chain.size}"
    puts "="*70
  end

  def save_chain(chain, name)
    filename = "chains/#{name.downcase.tr(' ', '_')}.json"
    FileUtils.mkdir_p("chains")
    File.write(filename, JSON.pretty_generate(chain))
    puts "✓ Saved to #{filename}"
  end

  def generate_exploration_batch(count: 10)
    puts "\n╔═══════════════════════════════════════════════════════════╗"
    puts "║     CHAIN EXPLORATION MODE                                ║"
    puts "╚═══════════════════════════════════════════════════════════╝"
    
    chains = []
    
    count.times do |i|
      puts "\nGenerating chain #{i + 1}/#{count}..."
      chain = generate_random_chain(length: rand(4..8))
      next if chain.empty?
      
      chains << chain
      display_chain(chain, title: "Random Chain ##{i + 1}")
      save_chain(chain, "random_#{i + 1}")
      
      sleep 0.5
    end
    
    puts "\n✓ Generated #{chains.size} chains"
    puts "✓ Saved to chains/ directory"
  end
end

if __FILE__ == $0
  generator = ChainGenerator.new
  
  command = ARGV[0] || "random"
  
  case command
  when "random"
    length = (ARGV[1] || 5).to_i
    chain = generator.generate_random_chain(length: length)
    generator.display_chain(chain)
  when "cinematic"
    chain = generator.generate_cinematic_chain
    generator.display_chain(chain, title: "Cinematic Chain")
  when "psychedelic"
    chain = generator.generate_psychedelic_chain
    generator.display_chain(chain, title: "Psychedelic Chain")
  when "glitch"
    chain = generator.generate_glitch_art_chain
    generator.display_chain(chain, title: "Glitch Art Chain")
  when "explore"
    count = (ARGV[1] || 10).to_i
    generator.generate_exploration_batch(count: count)
  else
    puts "Usage: ruby chain_generator.rb [random|cinematic|psychedelic|glitch|explore] [length/count]"
  end
end
