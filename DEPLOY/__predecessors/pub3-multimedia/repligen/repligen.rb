#!/usr/bin/env ruby
# frozen_string_literal: true

# Interactive Repligen - AI Generation Orchestrator
# Version: 4.1.0 - Interactive IRB-style

require "json"

# Bootstrap: ensure dependencies
def ensure_gems
  gems_ok = true
  
  # Check sqlite3
  begin
    require "sqlite3"
  rescue LoadError
    puts "[repligen] Installing sqlite3..."
    system("gem install sqlite3 --no-document")
    require "sqlite3"
  end
  
  # Check tty-prompt for interactive UI
  begin
    require "tty-prompt"
  rescue LoadError
    puts "[repligen] Installing tty-prompt..."
    system("gem install tty-prompt --no-document")
    require "tty-prompt"
  end
  
  gems_ok
end

puts "\n🎨 REPLIGEN - Interactive AI Generation"
puts "=" * 60

ensure_gems

require_relative "lib/config"
require_relative "lib/db"
require_relative "lib/api"
require_relative "lib/chain"

prompt = TTY::Prompt.new

# Main interactive menu
loop do
  puts "\n" + "=" * 60
  choice = prompt.select("What would you like to do?", cycle: true) do |menu|
    menu.choice "Generate with LoRA URL", :lora
    menu.choice "Sync models from Replicate", :sync
    menu.choice "Search models", :search
    menu.choice "Show statistics", :stats
    menu.choice "Run chain workflow", :chain
    menu.choice "Exit", :exit
  end
  
  case choice
  when :lora
    puts "\n📸 LoRA Model Generation"
    puts "-" * 60
    
    lora_url = prompt.ask("LoRA model URL (e.g., replicate.com/owner/model):") do |q|
      q.required true
      q.validate /replicate\.com\/[\w-]+\/[\w-]+/
      q.messages[:valid?] = "Must be a valid Replicate model URL"
    end
    
    # Extract model ID from URL
    if lora_url =~ /replicate\.com\/([\w-]+\/[\w-]+)/
      model_id = $1
      
      prompt_text = prompt.ask("Generation prompt:", default: "masterpiece, best quality, cinematic lighting")
      
      puts "\n🚀 Generating with #{model_id}..."
      puts "Prompt: #{prompt_text}"
      
      begin
        token = Repligen::Config.load
        api = Repligen::API.new(token)
        
        output = api.predict(model_id, { prompt: prompt_text })
        
        # Save output
        output_dir = "output/#{model_id.gsub('/', '_')}_#{Time.now.to_i}"
        FileUtils.mkdir_p(output_dir)
        
        if output.is_a?(Array)
          output.each_with_index do |url, i|
            filename = File.join(output_dir, "image_#{i}.png")
            puts "💾 Downloading #{url}..."
            system("curl -s -o '#{filename}' '#{url}'")
            puts "✓ Saved: #{filename}"
          end
        elsif output.is_a?(String)
          filename = File.join(output_dir, "output.png")
          puts "💾 Downloading #{output}..."
          system("curl -s -o '#{filename}' '#{output}'")
          puts "✓ Saved: #{filename}"
        end
        
        puts "\n✓ Complete! Output: #{output_dir}"
        
        if prompt.yes?("Process with postpro?")
          puts "🎬 Running postpro..."
          system("ruby ../postpro/postpro.rb")
        end
        
      rescue => e
        puts "\n✗ Error: #{e.message}"
      end
    end
    
  when :sync
    puts "\n📡 Sync Models from Replicate"
    puts "-" * 60
    
    if File.exist?("repligen.db")
      db = Repligen::Database.new
      current_count = db.count
      puts "Current database: #{current_count} models"
      
      next unless prompt.yes?("Sync more models?")
    end
    
    limit = prompt.ask("How many models to sync?", default: 100, convert: :int)
    
    puts "\n⏳ Syncing #{limit} models..."
    exec "ruby", File.join(__dir__, "bin/repligen"), "sync", limit.to_s
    
  when :search
    puts "\n🔍 Search Models"
    puts "-" * 60
    
    query = prompt.ask("Search query:")
    exec "ruby", File.join(__dir__, "bin/repligen"), "search", query
    
  when :stats
    puts "\n📊 Database Statistics"
    puts "-" * 60
    exec "ruby", File.join(__dir__, "bin/repligen"), "stats"
    
  when :chain
    puts "\n🎬 Chain Workflow"
    puts "-" * 60
    
    template = prompt.select("Choose template:") do |menu|
      menu.choice "Masterpiece (complex)", "masterpiece"
      menu.choice "Quick (fast)", "quick"
    end
    
    exec "ruby", File.join(__dir__, "bin/repligen"), "chain", template
    
  when :exit
    puts "\n👋 Goodbye!"
    exit 0
  end
end
