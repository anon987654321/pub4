# frozen_string_literal: true

# encoding: utf-8

require_relative 'chatbot'
require_relative '../../lib/multi_llm_manager'
require_relative '../../lib/weaviate_integration'
require 'ferrum'
require 'base64'
require 'json'

module Assistants
  # Enhanced SnapchatAssistant with dynamic UI element detection and automated friend discovery
  class SnapchatAssistant < ChatbotAssistant
    attr_accessor :browser, :llm_manager, :weaviate, :ui_cache, :friend_discovery_cache

    def initialize
      super()
      @browser = Ferrum::Browser.new(headless: true, window_size: [1280, 720])
      @llm_manager = MultiLLMManager.new
      @weaviate = WeaviateIntegration.new
      @ui_cache = {}
      @friend_discovery_cache = {}
      
      puts '👻 Enhanced SnapchatAssistant initialized with AI-powered UI detection!'
    end

    # Dynamic UI element detection using screenshot analysis
    def detect_snapchat_ui_elements(action_context = 'general')
      puts "🔍 Detecting Snapchat UI elements for: #{action_context}"
      
      # Generate unique cache key based on current page state
      page_state = capture_page_state
      cache_key = generate_ui_cache_key(page_state, action_context)
      
      if @ui_cache.key?(cache_key)
        puts "⚡ Using cached UI element detection"
        return @ui_cache[cache_key]
      end
      
      # Capture screenshot and HTML for analysis
      screenshot_base64 = @browser.screenshot(encoding: :base64)
      html_content = extract_relevant_html
      
      # Use LLM to identify UI elements
      ui_elements = analyze_snapchat_ui_with_llm(html_content, screenshot_base64, action_context)
      
      # Validate and refine detected elements
      validated_elements = validate_and_refine_ui_elements(ui_elements)
      
      # Cache results for future use
      @ui_cache[cache_key] = validated_elements
      
      puts "🎯 Detected #{validated_elements.keys.size} UI elements"
      validated_elements
    end

    # Automated friend discovery and engagement
    def discover_and_engage_friends(discovery_criteria = {})
      puts "🌟 Starting automated friend discovery"
      
      discovery_results = []
      
      # Navigate to friend discovery areas
      discovery_locations = [
        { name: 'Quick Add', url: 'https://snapchat.com/add', context: 'quick_add' },
        { name: 'Search', url: 'https://snapchat.com/search', context: 'search' },
        { name: 'Discover', url: 'https://snapchat.com/discover', context: 'discover' }
      ]
      
      discovery_locations.each do |location|
        puts "🔍 Exploring #{location[:name]} for friends"
        
        begin
          @browser.goto(location[:url])
          sleep(3) # Allow page to load
          
          # Detect UI elements for this context
          ui_elements = detect_snapchat_ui_elements(location[:context])
          
          # Find potential friends
          potential_friends = find_potential_friends(ui_elements, discovery_criteria)
          
          # Engage with found friends
          engagement_results = engage_with_potential_friends(potential_friends, ui_elements)
          
          discovery_results.concat(engagement_results.map do |result|
            result.merge(discovery_location: location[:name])
          end)
          
        rescue StandardError => e
          puts "❌ Error in #{location[:name]}: #{e.message}"
          discovery_results << {
            discovery_location: location[:name],
            error: e.message,
            status: :failed
          }
        end
      end
      
      summary = generate_discovery_summary(discovery_results)
      puts "🎉 Friend discovery complete: #{summary[:total_attempts]} attempts, #{summary[:successful_engagements]} successful engagements"
      
      {
        results: discovery_results,
        summary: summary,
        completed_at: Time.now
      }
    end

    # CSS class identification via LLM analysis  
    def identify_css_classes_for_action(action_type, target_element_description)
      puts "🎨 Identifying CSS classes for #{action_type} on #{target_element_description}"
      
      # Take screenshot of current state
      screenshot_base64 = @browser.screenshot(encoding: :base64)
      html_snippet = extract_html_around_element(target_element_description)
      
      # Create specialized prompt for CSS class identification
      css_identification_prompt = build_css_identification_prompt(
        action_type, 
        target_element_description, 
        html_snippet, 
        screenshot_base64
      )
      
      # Get LLM analysis
      css_analysis = @llm_manager.process_request(
        css_identification_prompt,
        context: {
          action_type: action_type,
          element_description: target_element_description,
          platform: 'snapchat'
        }
      )
      
      # Parse and validate CSS selectors
      parsed_selectors = parse_css_selectors_from_response(css_analysis)
      validated_selectors = validate_css_selectors(parsed_selectors)
      
      {
        identified_selectors: validated_selectors,
        confidence_score: calculate_selector_confidence(validated_selectors),
        raw_analysis: css_analysis,
        identified_at: Time.now
      }
    end

    # Send snap or message with dynamic UI handling
    def send_snap_or_message(friend_identifier, content, content_type: :text)
      puts "📤 Sending #{content_type} to #{friend_identifier}"
      
      begin
        # Navigate to messaging interface
        navigate_to_messaging_interface(friend_identifier)
        
        # Detect current UI elements
        ui_elements = detect_snapchat_ui_elements('messaging')
        
        case content_type
        when :text
          result = send_text_message(content, ui_elements)
        when :snap
          result = send_snap(content, ui_elements)
        when :media
          result = send_media_message(content, ui_elements)
        else
          result = { status: :error, message: "Unsupported content type: #{content_type}" }
        end
        
        puts "✅ Message sent successfully!" if result[:status] == :success
        result
        
      rescue StandardError => e
        puts "❌ Failed to send message: #{e.message}"
        { status: :error, error: e.message }
      end
    end

    # Advanced friend analysis before engagement
    def analyze_potential_friend(friend_profile_data)
      puts "🔍 Analyzing potential friend: #{friend_profile_data[:username] || 'Unknown'}"
      
      # Create comprehensive analysis prompt
      analysis_prompt = build_friend_analysis_prompt(friend_profile_data)
      
      # Get AI analysis
      friend_analysis = @llm_manager.process_request(
        analysis_prompt,
        context: {
          platform: 'snapchat',
          analysis_type: 'friend_compatibility',
          profile_data: friend_profile_data
        }
      )
      
      # Structure the analysis
      structured_analysis = parse_friend_analysis(friend_analysis)
      
      # Store in vector database for future reference
      store_friend_analysis(structured_analysis, friend_profile_data)
      
      puts "📊 Friend analysis complete - Compatibility: #{structured_analysis[:compatibility_score]}/10"
      structured_analysis
    end

    # Cleanup browser resources
    def cleanup
      @browser&.quit
      puts "🧹 SnapchatAssistant cleaned up"
    end

    private

    # Capture current page state for caching
    def capture_page_state
      {
        url: @browser.current_url,
        title: (@browser.title rescue 'unknown'),
        viewport: @browser.viewport_size,
        timestamp: Time.now.to_i
      }
    end

    # Generate cache key for UI elements
    def generate_ui_cache_key(page_state, action_context)
      state_string = "#{page_state[:url]}_#{action_context}_#{page_state[:viewport].join('x')}"
      Digest::SHA256.hexdigest(state_string)[0..15]
    end

    # Extract relevant HTML for analysis
    def extract_relevant_html
      # Focus on interactive elements and main content areas
      relevant_selectors = [
        'button', 'input', '[role="button"]', '.snap-*', '[class*="snap"]',
        'form', 'textarea', '[data-testid]', '[aria-label]'
      ]
      
      relevant_html = ""
      relevant_selectors.each do |selector|
        elements = @browser.css(selector)
        elements.each do |element|
          relevant_html += element.inner_html rescue ""
        end
      end
      
      relevant_html[0..5000] # Limit size for LLM processing
    end

    # Analyze Snapchat UI using LLM
    def analyze_snapchat_ui_with_llm(html_content, screenshot_base64, action_context)
      ui_analysis_prompt = <<~PROMPT
        Analyze this Snapchat interface screenshot and HTML to identify interactive UI elements for #{action_context}.
        
        Please identify CSS selectors for these common Snapchat actions:
        #{get_snapchat_element_types(action_context).map { |elem| "- #{elem}" }.join("\n")}
        
        HTML Content: #{html_content}
        Screenshot: data:image/png;base64,#{screenshot_base64}
        
        Provide CSS selectors in JSON format. Focus on:
        1. Unique, stable selectors that won't break with minor UI changes
        2. Data attributes and aria-labels when available
        3. Fallback selectors using class patterns
        
        Example format: {"add_friend_button": "button[data-testid='add-friend']", "message_input": "textarea[placeholder*='message']"}
      PROMPT
      
      response = @llm_manager.process_request(ui_analysis_prompt)
      
      begin
        JSON.parse(response)
      rescue JSON::ParserError
        extract_json_from_text(response) || {}
      end
    end

    # Get Snapchat-specific element types for different contexts
    def get_snapchat_element_types(action_context)
      case action_context
      when 'quick_add'
        ['add_friend_button', 'friend_suggestion_card', 'username_text', 'dismiss_button']
      when 'search'
        ['search_input', 'search_result_item', 'user_profile_link', 'add_button']
      when 'discover'
        ['story_tile', 'follow_button', 'profile_image', 'username_link']
      when 'messaging'
        ['message_input', 'send_button', 'camera_button', 'attachment_button', 'emoji_button']
      when 'camera'
        ['capture_button', 'switch_camera_button', 'flash_toggle', 'filter_button']
      else
        ['generic_button', 'clickable_element', 'input_field', 'navigation_item']
      end
    end

    # Validate and refine UI elements
    def validate_and_refine_ui_elements(ui_elements)
      validated = {}
      
      ui_elements.each do |element_name, selector|
        begin
          # Test if selector works
          element = @browser.at_css(selector)
          if element
            # Check if element is actually interactive
            if element_is_interactive?(element)
              validated[element_name.to_sym] = selector
              puts "✅ Validated interactive element: #{element_name}"
            else
              puts "⚠️  Element found but not interactive: #{element_name}"
            end
          else
            # Try to find alternative selectors
            alternative = find_alternative_selector(element_name, selector)
            if alternative
              validated[element_name.to_sym] = alternative
              puts "🔄 Found alternative selector for: #{element_name}"
            else
              puts "❌ Could not validate selector: #{element_name}"
            end
          end
        rescue StandardError => e
          puts "❌ Error validating #{element_name}: #{e.message}"
        end
      end
      
      validated
    end

    # Check if element is interactive
    def element_is_interactive?(element)
      return false unless element
      
      interactive_tags = ['button', 'input', 'textarea', 'select', 'a']
      interactive_roles = ['button', 'link', 'textbox', 'searchbox']
      
      tag_name = element.tag_name.downcase
      role = element.attribute('role')
      
      interactive_tags.include?(tag_name) || 
      interactive_roles.include?(role) ||
      element.attribute('onclick') ||
      element.attribute('href') ||
      element.attribute('tabindex')
    end

    # Find alternative selector if primary fails
    def find_alternative_selector(element_name, original_selector)
      # Common alternative patterns for Snapchat
      alternatives = [
        original_selector.gsub(/\[data-testid=['"](.*?)['"]\]/, '[aria-label*="\\1"]'),
        original_selector.gsub(/button/, '[role="button"]'),
        original_selector.gsub(/input/, '[type="text"], [type="search"]'),
        "#{original_selector}, #{original_selector.gsub(/^/, '.')}" # Add class-based fallback
      ]
      
      alternatives.each do |alt_selector|
        begin
          element = @browser.at_css(alt_selector)
          return alt_selector if element && element_is_interactive?(element)
        rescue StandardError
          next
        end
      end
      
      nil
    end

    # Find potential friends based on criteria
    def find_potential_friends(ui_elements, criteria)
      potential_friends = []
      
      # Look for friend suggestion elements
      if ui_elements[:friend_suggestion_card]
        friend_cards = @browser.css(ui_elements[:friend_suggestion_card])
        
        friend_cards.each do |card|
          friend_data = extract_friend_data_from_card(card)
          
          if meets_discovery_criteria?(friend_data, criteria)
            potential_friends << friend_data
          end
        end
      end
      
      # Look for search results if we're in search context
      if ui_elements[:search_result_item]
        result_items = @browser.css(ui_elements[:search_result_item])
        
        result_items.each do |item|
          friend_data = extract_friend_data_from_search_result(item)
          
          if meets_discovery_criteria?(friend_data, criteria)
            potential_friends << friend_data
          end
        end
      end
      
      puts "🔍 Found #{potential_friends.size} potential friends"
      potential_friends
    end

    # Extract friend data from suggestion card
    def extract_friend_data_from_card(card)
      begin
        {
          username: extract_text_from_element(card, ['[data-testid*="username"]', '.username', 'h3', 'strong']),
          display_name: extract_text_from_element(card, ['[data-testid*="display"]', '.display-name', 'h2']),
          mutual_friends: extract_text_from_element(card, ['[data-testid*="mutual"]', '.mutual-friends']),
          profile_image: extract_image_from_element(card, ['img[src*="profile"]', 'img[alt*="profile"]', 'img']),
          add_button_element: card.at_css('button[data-testid*="add"], button[aria-label*="add"], .add-button'),
          source: 'suggestion_card'
        }
      rescue StandardError => e
        puts "⚠️  Error extracting friend data from card: #{e.message}"
        { username: 'unknown', source: 'suggestion_card', error: e.message }
      end
    end

    # Check if friend meets discovery criteria
    def meets_discovery_criteria?(friend_data, criteria)
      return true if criteria.empty?
      
      criteria.each do |criterion, value|
        case criterion
        when :has_mutual_friends
          return false if value && (!friend_data[:mutual_friends] || friend_data[:mutual_friends].empty?)
        when :username_pattern
          return false unless friend_data[:username]&.match?(Regexp.new(value, Regexp::IGNORECASE))
        when :exclude_verified
          return false if value && friend_data[:verified]
        when :min_mutual_friends
          mutual_count = extract_mutual_friends_count(friend_data[:mutual_friends])
          return false if mutual_count < value
        end
      end
      
      true
    end

    # Engage with potential friends
    def engage_with_potential_friends(potential_friends, ui_elements)
      engagement_results = []
      
      potential_friends.each do |friend_data|
        puts "👋 Engaging with potential friend: #{friend_data[:username]}"
        
        # Analyze friend before engaging
        analysis = analyze_potential_friend(friend_data)
        
        # Decide whether to add based on analysis
        if should_add_friend?(analysis)
          result = add_friend(friend_data, ui_elements)
          engagement_results << result.merge(friend_data: friend_data, analysis: analysis)
        else
          engagement_results << {
            friend_data: friend_data,
            action: :skipped,
            reason: 'Low compatibility score',
            analysis: analysis
          }
        end
        
        # Add delay to appear more natural
        sleep(rand(2..4))
      end
      
      engagement_results
    end

    # Helper methods for data extraction
    def extract_text_from_element(parent_element, selectors)
      selectors.each do |selector|
        element = parent_element.at_css(selector)
        return element.text.strip if element && !element.text.strip.empty?
      end
      nil
    end

    def extract_image_from_element(parent_element, selectors)
      selectors.each do |selector|
        element = parent_element.at_css(selector)
        return element.attribute('src') if element
      end
      nil
    end

    def extract_mutual_friends_count(mutual_friends_text)
      return 0 unless mutual_friends_text
      
      # Extract number from text like "3 mutual friends" or "5 friends in common"
      match = mutual_friends_text.match(/(\d+)/)
      match ? match[1].to_i : 0
    end

    # Build CSS identification prompt
    def build_css_identification_prompt(action_type, target_description, html_snippet, screenshot)
      <<~PROMPT
        I need to identify the correct CSS selector for a specific action on Snapchat.
        
        Action: #{action_type}
        Target Element: #{target_description}
        
        HTML around target area:
        #{html_snippet}
        
        Screenshot: data:image/png;base64,#{screenshot}
        
        Please analyze the HTML and screenshot to identify the most reliable CSS selector for the target element.
        Consider:
        1. Data attributes (data-testid, data-*)
        2. ARIA labels and roles
        3. Unique class combinations
        4. Position relative to other elements
        
        Provide your answer as JSON: {"primary_selector": "...", "fallback_selectors": ["...", "..."], "confidence": 0.95}
      PROMPT
    end

    # Parse CSS selectors from LLM response
    def parse_css_selectors_from_response(response)
      begin
        parsed = JSON.parse(response)
        return parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        # Try to extract JSON from text
        json_match = response.match(/\{.*\}/m)
        if json_match
          begin
            return JSON.parse(json_match[0])
          rescue JSON::ParserError
            # Fallback to manual extraction
          end
        end
      end
      
      # Manual extraction as fallback
      selectors = {}
      response.scan(/"([^"]+)":\s*"([^"]+)"/) do |key, value|
        selectors[key] = value
      end
      
      selectors
    end

    # Validate CSS selectors
    def validate_css_selectors(selectors)
      validated = {}
      
      selectors.each do |key, selector|
        begin
          element = @browser.at_css(selector)
          validated[key] = selector if element
        rescue StandardError
          # Selector is invalid, skip it
        end
      end
      
      validated
    end

    # Calculate confidence score for selectors
    def calculate_selector_confidence(validated_selectors)
      return 0 if validated_selectors.empty?
      
      # Simple confidence based on number of validated selectors and their quality
      base_confidence = validated_selectors.size * 10
      
      # Bonus for data attributes and ARIA labels (more reliable)
      quality_bonus = validated_selectors.values.count { |sel| sel.include?('data-') || sel.include?('aria-') } * 15
      
      [(base_confidence + quality_bonus), 100].min
    end

    # Build friend analysis prompt
    def build_friend_analysis_prompt(friend_profile_data)
      <<~PROMPT
        Analyze this potential Snapchat friend for compatibility and engagement potential.
        
        Profile Data:
        - Username: #{friend_profile_data[:username]}
        - Display Name: #{friend_profile_data[:display_name]}
        - Mutual Friends: #{friend_profile_data[:mutual_friends]}
        - Source: #{friend_profile_data[:source]}
        
        Please provide analysis including:
        1. Compatibility score (1-10)
        2. Engagement potential (low/medium/high)
        3. Red flags or concerns
        4. Recommended interaction approach
        5. Overall recommendation (add/skip)
        
        Consider factors like mutual connections, username patterns, and profile completeness.
        Provide response as JSON with structured analysis.
      PROMPT
    end

    # Parse friend analysis response
    def parse_friend_analysis(analysis_response)
      begin
        JSON.parse(analysis_response)
      rescue JSON::ParserError
        # Extract key metrics manually
        {
          compatibility_score: extract_score_from_text(analysis_response, 'compatibility'),
          engagement_potential: extract_level_from_text(analysis_response, 'engagement'),
          recommendation: extract_recommendation_from_text(analysis_response),
          concerns: extract_concerns_from_text(analysis_response),
          raw_analysis: analysis_response
        }
      end
    end

    # Store friend analysis in vector database
    def store_friend_analysis(analysis, friend_data)
      @weaviate.store_document(
        "snapchat_friend_analysis_#{friend_data[:username]}",
        analysis.to_json,
        {
          type: 'snapchat_friend_analysis',
          username: friend_data[:username],
          compatibility_score: analysis[:compatibility_score] || 5,
          analyzed_at: Time.now.to_i
        }
      )
    end

    # Decide whether to add friend based on analysis
    def should_add_friend?(analysis)
      compatibility_score = analysis[:compatibility_score] || analysis['compatibility_score'] || 5
      compatibility_score >= 6 # Add friends with compatibility score of 6 or higher
    end

    # Add friend action
    def add_friend(friend_data, ui_elements)
      begin
        if friend_data[:add_button_element]
          friend_data[:add_button_element].click
          sleep(1)
          
          {
            action: :add_friend,
            status: :success,
            username: friend_data[:username],
            timestamp: Time.now
          }
        else
          {
            action: :add_friend,
            status: :failed,
            reason: 'Add button not found',
            username: friend_data[:username]
          }
        end
      rescue StandardError => e
        {
          action: :add_friend,
          status: :error,
          error: e.message,
          username: friend_data[:username]
        }
      end
    end

    # Generate discovery summary
    def generate_discovery_summary(results)
      successful = results.count { |r| r[:status] == :success }
      failed = results.count { |r| r[:status] == :failed }
      errors = results.count { |r| r[:status] == :error }
      skipped = results.count { |r| r[:action] == :skipped }
      
      {
        total_attempts: results.size,
        successful_engagements: successful,
        failed_attempts: failed,
        errors: errors,
        skipped: skipped,
        success_rate: results.empty? ? 0 : (successful.to_f / results.size * 100).round(1)
      }
    end

    # Extract JSON from text response
    def extract_json_from_text(text)
      json_match = text.match(/\{.*\}/m)
      return nil unless json_match
      
      begin
        JSON.parse(json_match[0])
      rescue JSON::ParserError
        nil
      end
    end

    # Helper methods for text analysis
    def extract_score_from_text(text, score_type)
      pattern = /#{score_type}[:\-]*\s*(\d+(?:\.\d+)?)/i
      match = text.match(pattern)
      match ? match[1].to_f : 5.0
    end

    def extract_level_from_text(text, level_type)
      pattern = /#{level_type}[:\-]*\s*(low|medium|high)/i
      match = text.match(pattern)
      match ? match[1].downcase : 'medium'
    end

    def extract_recommendation_from_text(text)
      if text.match(/recommend.*add|should.*add|add.*recommend/i)
        'add'
      elsif text.match(/skip|avoid|not.*recommend/i)
        'skip'
      else
        'uncertain'
      end
    end

    def extract_concerns_from_text(text)
      concerns_section = text.match(/(?:red flags?|concerns?):\s*(.*?)(?:\n\n|\n[A-Z]|\z)/mi)
      return [] unless concerns_section
      
      concerns_section[1].scan(/(?:^|\n)(?:\d+\.|\-)\s*(.+)/).flatten
    end

    # Additional helper methods
    def navigate_to_messaging_interface(friend_identifier)
      # Navigate to chat with specific friend
      chat_url = "https://snapchat.com/chat/#{friend_identifier}"
      @browser.goto(chat_url)
      sleep(2)
    end

    def send_text_message(content, ui_elements)
      if ui_elements[:message_input] && ui_elements[:send_button]
        @browser.at_css(ui_elements[:message_input]).set(content)
        @browser.at_css(ui_elements[:send_button]).click
        { status: :success, content: content, type: :text }
      else
        { status: :failed, reason: 'Message input or send button not found' }
      end
    end

    def send_snap(content, ui_elements)
      # Placeholder for snap sending logic
      { status: :not_implemented, message: 'Snap sending not yet implemented' }
    end

    def send_media_message(content, ui_elements)
      # Placeholder for media message sending
      { status: :not_implemented, message: 'Media message sending not yet implemented' }
    end

    def extract_friend_data_from_search_result(result_element)
      # Similar to extract_friend_data_from_card but for search results
      {
        username: extract_text_from_element(result_element, ['[data-testid*="username"]', '.username']),
        display_name: extract_text_from_element(result_element, ['[data-testid*="display"]', '.display-name']),
        profile_image: extract_image_from_element(result_element, ['img']),
        add_button_element: result_element.at_css('button[data-testid*="add"], .add-button'),
        source: 'search_result'
      }
    end

    def extract_html_around_element(target_description)
      # Extract HTML around elements that match the description
      # This is a simplified implementation
      @browser.body.inner_html[0..2000]
    end
  end
end