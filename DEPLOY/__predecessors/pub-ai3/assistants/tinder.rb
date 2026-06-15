# frozen_string_literal: true

# encoding: utf-8

require_relative 'chatbot'
require_relative '../../lib/multi_llm_manager'
require_relative '../../lib/weaviate_integration'
require 'ferrum'
require 'base64'
require 'json'

module Assistants
  # Enhanced TinderAssistant with LLM-based screenshot analysis and profile analysis
  class TinderAssistant < ChatbotAssistant
    attr_accessor :browser, :llm_manager, :weaviate, :profile_analysis_cache
    
    def initialize
      super()
      @browser = Ferrum::Browser.new(headless: true, window_size: [1280, 720])
      @llm_manager = MultiLLMManager.new
      @weaviate = WeaviateIntegration.new
      @profile_analysis_cache = {}
      @dynamic_css_cache = {}
      
      puts '💖 Enhanced TinderAssistant initialized with AI-powered profile analysis!'
    end

    # Profile analysis and automated engagement
    def analyze_profile(user_id_or_url)
      puts "🔍 Analyzing profile: #{user_id_or_url}"
      
      profile_url = normalize_profile_url(user_id_or_url)
      
      # Check cache first
      cache_key = generate_cache_key(profile_url)
      if @profile_analysis_cache.key?(cache_key)
        puts "📋 Using cached profile analysis"
        return @profile_analysis_cache[cache_key]
      end
      
      begin
        # Navigate to profile and take screenshot
        @browser.goto(profile_url)
        sleep(3) # Allow page to load
        
        screenshot_base64 = @browser.screenshot(encoding: :base64)
        html_content = @browser.body.inner_html
        
        # AI-powered profile analysis
        profile_analysis = perform_ai_profile_analysis(html_content, screenshot_base64, profile_url)
        
        # Store in cache and vector database
        @profile_analysis_cache[cache_key] = profile_analysis
        store_profile_analysis(profile_analysis)
        
        puts "✅ Profile analysis complete"
        profile_analysis
        
      rescue StandardError => e
        puts "❌ Profile analysis failed: #{e.message}"
        { error: e.message, timestamp: Time.now }
      end
    end

    # Dynamic CSS class detection using LLM analysis of screenshots
    def detect_ui_elements(action_type)
      puts "🎨 Detecting UI elements for action: #{action_type}"
      
      # Check cache first
      page_signature = generate_page_signature
      cache_key = "#{action_type}_#{page_signature}"
      
      if @dynamic_css_cache.key?(cache_key)
        puts "⚡ Using cached CSS selectors"
        return @dynamic_css_cache[cache_key]
      end
      
      # Take fresh screenshot and analyze
      screenshot_base64 = @browser.screenshot(encoding: :base64)
      html_content = @browser.body.inner_html
      
      # Use LLM to identify CSS selectors
      css_selectors = analyze_ui_elements_with_llm(html_content, screenshot_base64, action_type)
      
      # Validate selectors work
      validated_selectors = validate_css_selectors(css_selectors)
      
      # Cache results
      @dynamic_css_cache[cache_key] = validated_selectors
      
      puts "🎯 Detected #{validated_selectors.keys.size} UI elements"
      validated_selectors
    end

    # Message customization based on profile analysis
    def generate_customized_message(profile_analysis, message_style: :friendly)
      puts "💬 Generating customized message based on profile analysis"
      
      # Extract key insights from profile
      interests = profile_analysis[:interests] || []
      personality_traits = profile_analysis[:personality_traits] || []
      bio_highlights = profile_analysis[:bio_highlights] || []
      
      # Create context for LLM
      context = {
        interests: interests,
        personality_traits: personality_traits,
        bio_highlights: bio_highlights,
        message_style: message_style,
        platform: 'tinder'
      }
      
      # Generate message using LLM
      message_prompt = build_message_generation_prompt(context)
      customized_message = @llm_manager.process_request(message_prompt, context: context)
      
      # Validate message quality
      message_quality = assess_message_quality(customized_message, profile_analysis)
      
      result = {
        message: customized_message,
        quality_score: message_quality[:score],
        confidence: message_quality[:confidence],
        reasoning: message_quality[:reasoning],
        generated_at: Time.now
      }
      
      puts "✨ Generated message with quality score: #{message_quality[:score]}/10"
      result
    end

    # Send customized message
    def send_customized_message(profile_url, message_data)
      puts "📤 Sending customized message to: #{profile_url}"
      
      begin
        # Navigate to profile
        @browser.goto(profile_url)
        sleep(2)
        
        # Detect message UI elements
        ui_elements = detect_ui_elements('send_message')
        
        # Find and click message button
        if ui_elements[:message_button]
          @browser.at_css(ui_elements[:message_button]).click
          sleep(1)
          
          # Type message
          if ui_elements[:message_input]
            @browser.at_css(ui_elements[:message_input]).focus
            @browser.at_css(ui_elements[:message_input]).set(message_data[:message])
            sleep(1)
            
            # Send message
            if ui_elements[:send_button]
              @browser.at_css(ui_elements[:send_button]).click
              puts "✅ Message sent successfully!"
              
              return {
                status: :success,
                message: message_data[:message],
                sent_at: Time.now
              }
            else
              puts "❌ Could not find send button"
            end
          else
            puts "❌ Could not find message input field"
          end
        else
          puts "❌ Could not find message button"
        end
        
        { status: :failed, reason: "UI elements not found" }
        
      rescue StandardError => e
        puts "❌ Failed to send message: #{e.message}"
        { status: :error, error: e.message }
      end
    end

    # Close browser and cleanup
    def cleanup
      @browser&.quit
      puts "🧹 TinderAssistant cleaned up"
    end

    private

    # Normalize profile URL
    def normalize_profile_url(user_id_or_url)
      if user_id_or_url.start_with?('http')
        user_id_or_url
      else
        "https://tinder.com/@#{user_id_or_url}"
      end
    end

    # Generate cache key for profile
    def generate_cache_key(profile_url)
      Digest::SHA256.hexdigest(profile_url)[0..15]
    end

    # Perform AI-powered profile analysis
    def perform_ai_profile_analysis(html_content, screenshot_base64, profile_url)
      analysis_prompt = build_profile_analysis_prompt(html_content, screenshot_base64)
      
      ai_analysis = @llm_manager.process_request(
        analysis_prompt,
        context: {
          url: profile_url,
          analysis_type: 'tinder_profile',
          timestamp: Time.now
        }
      )
      
      # Parse and structure the analysis
      structured_analysis = parse_profile_analysis(ai_analysis)
      
      {
        url: profile_url,
        ai_analysis: ai_analysis,
        structured_data: structured_analysis,
        analyzed_at: Time.now,
        confidence_score: calculate_analysis_confidence(structured_analysis)
      }
    end

    # Build profile analysis prompt
    def build_profile_analysis_prompt(html_content, screenshot_base64)
      <<~PROMPT
        Analyze this Tinder profile based on the provided HTML content and screenshot.
        
        Please provide a comprehensive analysis including:
        
        1. **Bio Analysis**: Extract and analyze the bio text, identifying personality traits, interests, and conversation starters
        2. **Photo Analysis**: Describe the photos and what they reveal about lifestyle, hobbies, and personality
        3. **Interest Tags**: List any interest/hobby tags visible
        4. **Conversation Starters**: Suggest 3-5 personalized conversation starters based on the profile
        5. **Compatibility Indicators**: Rate compatibility factors (shared interests, lifestyle, etc.)
        6. **Red Flags**: Identify any potential concerns or red flags
        7. **Overall Assessment**: Provide an overall compatibility score (1-10) with reasoning
        
        HTML Content (first 2000 chars): #{html_content[0..2000]}
        Screenshot: data:image/png;base64,#{screenshot_base64}
        
        Please provide your analysis in a structured JSON format.
      PROMPT
    end

    # Build LLM prompt for UI element detection
    def analyze_ui_elements_with_llm(html_content, screenshot_base64, action_type)
      ui_analysis_prompt = <<~PROMPT
        Analyze this Tinder web interface screenshot and HTML to identify CSS selectors for #{action_type} actions.
        
        Please identify the CSS selectors for these elements:
        
        For #{action_type}:
        #{get_element_types_for_action(action_type).map { |elem| "- #{elem}" }.join("\n")}
        
        HTML Content (first 1500 chars): #{html_content[0..1500]}
        Screenshot: data:image/png;base64,#{screenshot_base64}
        
        Please provide CSS selectors in JSON format: {"element_name": "css_selector"}
        Focus on unique, stable selectors that will work consistently.
      PROMPT
      
      response = @llm_manager.process_request(ui_analysis_prompt)
      
      begin
        JSON.parse(response)
      rescue JSON::ParserError
        # Extract JSON from response if it's embedded in text
        json_match = response.match(/\{.*\}/m)
        json_match ? JSON.parse(json_match[0]) : {}
      end
    end

    # Get element types needed for specific actions
    def get_element_types_for_action(action_type)
      case action_type
      when 'send_message'
        ['message_button', 'message_input', 'send_button', 'close_button']
      when 'profile_discovery'
        ['profile_card', 'like_button', 'pass_button', 'profile_image', 'profile_name']
      when 'match_dialog'
        ['match_notification', 'send_message_button', 'keep_swiping_button']
      else
        ['generic_button', 'input_field', 'clickable_element']
      end
    end

    # Validate CSS selectors actually work
    def validate_css_selectors(selectors)
      validated = {}
      
      selectors.each do |element_name, selector|
        begin
          element = @browser.at_css(selector)
          if element
            validated[element_name.to_sym] = selector
            puts "✅ Validated selector for #{element_name}: #{selector}"
          else
            puts "⚠️  Selector not found for #{element_name}: #{selector}"
          end
        rescue StandardError => e
          puts "❌ Invalid selector for #{element_name}: #{e.message}"
        end
      end
      
      validated
    end

    # Generate page signature for caching
    def generate_page_signature
      # Simple signature based on URL and page title
      url = @browser.current_url
      title = @browser.title rescue "unknown"
      Digest::SHA256.hexdigest("#{url}_#{title}")[0..15]
    end

    # Store profile analysis in vector database
    def store_profile_analysis(analysis)
      @weaviate.store_document(
        "tinder_profile_#{generate_cache_key(analysis[:url])}",
        analysis.to_json,
        {
          type: 'tinder_profile_analysis',
          url: analysis[:url],
          confidence_score: analysis[:confidence_score],
          analyzed_at: analysis[:analyzed_at].to_i
        }
      )
    end

    # Parse profile analysis from AI response
    def parse_profile_analysis(ai_response)
      begin
        # Try to parse as JSON first
        JSON.parse(ai_response)
      rescue JSON::ParserError
        # Extract structured information from text response
        {
          bio_analysis: extract_section(ai_response, 'Bio Analysis'),
          interests: extract_list(ai_response, 'Interest Tags'),
          conversation_starters: extract_list(ai_response, 'Conversation Starters'),
          compatibility_score: extract_score(ai_response, 'compatibility score'),
          red_flags: extract_list(ai_response, 'Red Flags'),
          overall_assessment: extract_section(ai_response, 'Overall Assessment')
        }
      end
    end

    # Build message generation prompt
    def build_message_generation_prompt(context)
      <<~PROMPT
        Generate a personalized opening message for a Tinder match based on their profile analysis.
        
        Profile Context:
        - Interests: #{context[:interests].join(', ')}
        - Personality Traits: #{context[:personality_traits].join(', ')}
        - Bio Highlights: #{context[:bio_highlights].join(', ')}
        - Message Style: #{context[:message_style]}
        
        Requirements:
        1. Keep it under 200 characters
        2. Be genuine and not overly flirty
        3. Reference something specific from their profile
        4. Ask an engaging question
        5. Match the requested style: #{context[:message_style]}
        
        Generate a single message that would likely get a response.
      PROMPT
    end

    # Assess message quality
    def assess_message_quality(message, profile_analysis)
      # Simple quality assessment - can be enhanced
      quality_factors = {
        length_appropriate: message.length.between?(20, 200),
        mentions_profile_detail: profile_analysis[:interests]&.any? { |interest| message.downcase.include?(interest.downcase) },
        asks_question: message.include?('?'),
        not_generic: !is_generic_message?(message)
      }
      
      score = quality_factors.values.count(true) * 2.5
      
      {
        score: score,
        confidence: score >= 7.5 ? :high : score >= 5 ? :medium : :low,
        reasoning: quality_factors
      }
    end

    # Check if message is generic
    def is_generic_message?(message)
      generic_phrases = ['hey', 'hi', 'how are you', 'whats up', 'nice pics']
      message_lower = message.downcase
      generic_phrases.any? { |phrase| message_lower.include?(phrase) }
    end

    # Calculate analysis confidence
    def calculate_analysis_confidence(analysis_data)
      confidence_factors = []
      
      confidence_factors << (analysis_data[:bio_analysis]&.length || 0) > 50
      confidence_factors << (analysis_data[:interests]&.size || 0) > 0
      confidence_factors << (analysis_data[:conversation_starters]&.size || 0) >= 3
      confidence_factors << analysis_data[:compatibility_score].to_i > 0
      
      (confidence_factors.count(true).to_f / confidence_factors.size * 100).round
    end

    # Helper methods for text extraction
    def extract_section(text, section_name)
      pattern = /#{section_name}[:\-]*\s*(.*?)(?=\n\n|\n[A-Z]|\z)/mi
      match = text.match(pattern)
      match ? match[1].strip : nil
    end

    def extract_list(text, section_name)
      section = extract_section(text, section_name)
      return [] unless section
      
      # Extract list items (lines starting with - or numbers)
      section.scan(/(?:^|\n)(?:\d+\.|\-)\s*(.+)/).flatten
    end

    def extract_score(text, score_type)
      pattern = /#{score_type}[:\-]*\s*(\d+(?:\.\d+)?)/i
      match = text.match(pattern)
      match ? match[1].to_f : 0
    end
  end
end