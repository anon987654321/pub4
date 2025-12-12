#!/usr/bin/env ruby
# frozen_string_literal: true

require "ferrum"
require "json"
require "net/http"
require "base64"

# LLM-Guided Web Scraper
# Uses Llama 3.3 70B to analyze screenshots and guide navigation

class LLMGuidedScraper
  def initialize
    @browser = Ferrum::Browser.new(headless: true, window_size: [1920, 1080])
    @token = ENV["REPLICATE_API_TOKEN"]
    @models_found = []
  end

  def ask_llm(prompt, screenshot_path = nil)
    body = {
      input: {
        prompt: prompt
      }
    }
    
    # If screenshot provided, encode and include
    if screenshot_path && File.exist?(screenshot_path)
      image_data = Base64.strict_encode64(File.read(screenshot_path))
      body[:input][:image] = "data:image/png;base64,#{image_data}"
    end
    
    uri = URI("https://api.replicate.com/v1/models/meta/llama-3.3-70b-instruct/predictions")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Token #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json
    
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    data = JSON.parse(res.body)
    
    # Wait for response
    prediction_id = data["id"]
    loop do
      sleep 2
      uri = URI("https://api.replicate.com/v1/predictions/#{prediction_id}")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Token #{@token}"
      
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      data = JSON.parse(res.body)
      
      if data["status"] == "succeeded"
        output = data["output"]
        return output.is_a?(Array) ? output.join : output
      elsif data["status"] == "failed"
        return nil
      end
      
      print "."
    end
  end

  def scrape_with_llm_guidance
    puts "\n╔═══════════════════════════════════════════════════════════╗"
    puts "║     LLM-GUIDED WEB SCRAPER (Llama 3.3 + Ferrum)         ║"
    puts "╚═══════════════════════════════════════════════════════════╝"
    
    @browser.goto("https://replicate.com/explore")
    sleep 3
    
    puts "\n1. Taking screenshot..."
    @browser.screenshot(path: "screenshots/explore_initial.png")
    
    puts "\n2. Asking LLM to analyze page structure..."
    analysis = ask_llm(<<~PROMPT, "screenshots/explore_initial.png")
      Analyze this screenshot of replicate.com/explore.
      
      Describe:
      1. How many model cards are visible?
      2. What CSS selectors or data attributes identify model cards?
      3. Is there pagination? What selector for next page?
      4. Are there filters or categories visible?
      
      Be specific about HTML/CSS selectors you observe.
    PROMPT
    
    puts "\n📊 LLM Analysis:"
    puts analysis[0..500] + "..." if analysis
    
    puts "\n3. Extracting page source..."
    html = @browser.body
    File.write("screenshots/page_source.html", html)
    puts "  Saved to: screenshots/page_source.html"
    
    puts "\n4. Asking LLM for extraction strategy..."
    strategy = ask_llm(<<~PROMPT)
      Given this HTML structure from replicate.com/explore, what JavaScript
      code would extract all model information (owner, name, description, run count)?
      
      HTML snippet:
      #{html[0..2000]}
      
      Return ONLY executable JavaScript code, no explanation.
    PROMPT
    
    puts "\n💡 LLM Extraction Strategy:"
    puts strategy[0..300] + "..." if strategy
    
    puts "\n5. Executing LLM-generated extraction..."
    begin
      models = @browser.evaluate(strategy)
      puts "  Extracted #{models.size rescue 0} models"
      @models_found.concat(models) if models.is_a?(Array)
    rescue => e
      puts "  Error: #{e.message}"
    end
    
    puts "\n" + "="*70
    puts "Models found: #{@models_found.size}"
    puts "="*70
    
    @models_found
  ensure
    @browser.quit
  end
end

if __FILE__ == $0
  scraper = LLMGuidedScraper.new
  scraper.scrape_with_llm_guidance
end
