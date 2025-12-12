#!/usr/bin/env ruby
# frozen_string_literal: true

require "ferrum"
require "json"
require "sqlite3"
require "fileutils"

# Advanced Model Scraper - Uses Ferrum + Screenshots for LLM guidance
# Goal: Index all 50,000+ models from replicate.com/explore

class AdvancedModelScraper
  def initialize
    @browser = Ferrum::Browser.new(
      headless: true,
      timeout: 30,
      window_size: [1920, 1080]
    )
    
    @db = SQLite3::Database.new("repligen_full_models.db")
    setup_database
  end

  def setup_database
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS models_full (
        id TEXT PRIMARY KEY,
        owner TEXT,
        name TEXT,
        description TEXT,
        tags TEXT,
        run_count INTEGER,
        featured BOOLEAN,
        page_number INTEGER,
        screenshot_path TEXT,
        indexed_at INTEGER
      )
    SQL
    
    puts "✓ Database initialized: repligen_full_models.db"
  end

  def take_screenshot(filename)
    FileUtils.mkdir_p("screenshots")
    path = "screenshots/#{filename}"
    @browser.screenshot(path: path)
    puts "  📸 Screenshot: #{path}"
    path
  end

  def get_page_source
    @browser.body
  end

  def extract_models_from_page
    # Extract model cards using JavaScript
    models = @browser.evaluate(<<~JS)
      Array.from(document.querySelectorAll('[data-testid="model-card"], .model-card, a[href*="/models/"]'))
        .map(card => {
          const link = card.href || card.querySelector('a')?.href || '';
          const owner = link.split('/')[3] || '';
          const name = link.split('/')[4] || '';
          const description = card.querySelector('.description, p')?.textContent?.trim() || '';
          const runCount = card.textContent.match(/([\\d,]+)\\s*runs?/i)?.[1]?.replace(/,/g, '') || '0';
          
          return {
            id: owner && name ? owner + '/' + name : null,
            owner: owner,
            name: name,
            description: description,
            run_count: parseInt(runCount) || 0
          };
        })
        .filter(m => m.id && m.id.includes('/'));
    JS
    
    models || []
  end

  def scrape_explore_page(page_number = 1)
    url = page_number == 1 ? 
      "https://replicate.com/explore" : 
      "https://replicate.com/explore?page=#{page_number}"
    
    puts "\n=== SCRAPING PAGE #{page_number} ==="
    puts "URL: #{url}"
    
    @browser.goto(url)
    sleep 3 # Wait for page load
    
    # Take screenshot for analysis
    screenshot = take_screenshot("explore_page_#{page_number}.png")
    
    # Extract models
    models = extract_models_from_page
    puts "  Found #{models.size} models on page"
    
    # Save to database
    models.each do |model|
      @db.execute(
        "INSERT OR REPLACE INTO models_full VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          model[:id],
          model[:owner],
          model[:name],
          model[:description],
          "", # tags
          model[:run_count],
          false,
          page_number,
          screenshot,
          Time.now.to_i
        ]
      )
    end
    
    # Check if there's a next page
    has_next = @browser.evaluate(<<~JS)
      !!document.querySelector('a[rel="next"], button:contains("Next"), [aria-label*="next"]');
    JS
    
    { models: models.size, has_next: has_next }
  end

  def scrape_all(max_pages = 100)
    puts "\n╔═══════════════════════════════════════════════════════════╗"
    puts "║     ADVANCED MODEL SCRAPER - FERRUM + SCREENSHOTS        ║"
    puts "╚═══════════════════════════════════════════════════════════╝"
    
    start_time = Time.now
    total_models = 0
    page = 1
    
    loop do
      break if page > max_pages
      
      result = scrape_explore_page(page)
      total_models += result[:models]
      
      break unless result[:has_next]
      
      page += 1
      sleep 2 # Rate limiting
    end
    
    duration = Time.now - start_time
    
    puts "\n" + "="*70
    puts "🎉 SCRAPING COMPLETE!"
    puts "="*70
    puts "Pages scraped: #{page}"
    puts "Models found: #{total_models}"
    puts "Duration: #{duration.round(1)}s"
    puts "Screenshots: screenshots/"
    puts "Database: repligen_full_models.db"
    puts "="*70
  ensure
    @browser.quit
  end

  def stats
    total = @db.execute("SELECT COUNT(*) FROM models_full")[0][0]
    pages = @db.execute("SELECT MAX(page_number) FROM models_full")[0][0]
    
    puts "\n=== DATABASE STATS ==="
    puts "Total models: #{total}"
    puts "Pages scraped: #{pages}"
    
    puts "\nTop 10 Most Popular:"
    @db.execute("SELECT id, run_count FROM models_full ORDER BY run_count DESC LIMIT 10").each do |row|
      puts "  #{row[0]}: #{row[1].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} runs"
    end
  end
end

if __FILE__ == $0
  scraper = AdvancedModelScraper.new
  
  command = ARGV[0] || "scrape"
  
  case command
  when "scrape"
    max_pages = (ARGV[1] || 10).to_i
    scraper.scrape_all(max_pages)
  when "stats"
    scraper.stats
  else
    puts "Usage: ruby advanced_scraper.rb [scrape|stats] [max_pages]"
  end
end
