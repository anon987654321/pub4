# frozen_string_literal: true

require_relative '../lib/universal_scraper'
require_relative '../lib/weaviate_integration'
require_relative '../lib/multi_llm_manager'
require_relative '../lib/cognitive_orchestrator'

module Assistants
  # Material Design Assistant - Advanced material analysis and design optimization
  # Integrates with UniversalScraper for comprehensive material data collection
  class MaterialDesignAssistant
    attr_accessor :scraper, :weaviate, :llm_manager, :cognitive_orchestrator

    def initialize
      @scraper = UniversalScraper.new
      @weaviate = WeaviateIntegration.new
      @llm_manager = MultiLLMManager.new
      @cognitive_orchestrator = CognitiveOrchestrator.new
      
      @material_database = {}
      @design_patterns = load_design_patterns
      @analysis_cache = {}
      
      puts "🎨 Material Design Assistant initialized"
    end

    # Analyze material properties and design characteristics
    def analyze_material(material_data)
      puts "🔬 Analyzing material: #{material_data[:name] || 'Unknown'}"
      
      analysis_key = generate_analysis_key(material_data)
      
      # Check cache first
      if @analysis_cache.key?(analysis_key)
        puts "📋 Using cached analysis"
        return @analysis_cache[analysis_key]
      end
      
      # Perform comprehensive analysis
      analysis = {
        material_id: SecureRandom.hex(8),
        timestamp: Time.now,
        basic_properties: analyze_basic_properties(material_data),
        design_compatibility: assess_design_compatibility(material_data),
        sustainability_score: calculate_sustainability_score(material_data),
        usage_recommendations: generate_usage_recommendations(material_data),
        color_analysis: analyze_color_properties(material_data),
        texture_analysis: analyze_texture_properties(material_data),
        performance_metrics: calculate_performance_metrics(material_data)
      }
      
      # Enhanced AI analysis using LLM
      ai_insights = @llm_manager.process_request(
        "Provide advanced material design insights for: #{material_data}",
        context: { 
          analysis: analysis,
          design_patterns: @design_patterns 
        }
      )
      
      analysis[:ai_insights] = ai_insights
      
      # Store in cache and vector database
      @analysis_cache[analysis_key] = analysis
      store_analysis_in_vector_db(analysis)
      
      puts "✅ Material analysis complete"
      analysis
    end

    # Scrape material data from web sources
    def scrape_material_data(url_or_query)
      puts "🌐 Scraping material data from: #{url_or_query}"
      
      begin
        if url_or_query.start_with?('http')
          # Direct URL scraping
          scraped_data = @scraper.scrape_url(url_or_query, {
            extract_images: true,
            extract_specifications: true,
            extract_technical_data: true
          })
        else
          # Search query scraping
          scraped_data = @scraper.search_and_scrape(url_or_query, {
            search_engines: ['google', 'bing', 'material_databases'],
            max_results: 10,
            filter_material_content: true
          })
        end
        
        # Process scraped data for material analysis
        processed_data = process_scraped_material_data(scraped_data)
        
        puts "📊 Scraped and processed #{processed_data.size} material entries"
        processed_data
        
      rescue StandardError => e
        puts "❌ Scraping failed: #{e.message}"
        []
      end
    end

    # Generate design recommendations based on material analysis
    def generate_design_recommendations(material_analysis, design_context = {})
      puts "💡 Generating design recommendations"
      
      recommendations = {
        primary_applications: suggest_primary_applications(material_analysis),
        design_patterns: suggest_compatible_patterns(material_analysis),
        color_schemes: suggest_color_schemes(material_analysis),
        combination_materials: suggest_material_combinations(material_analysis),
        sustainability_improvements: suggest_sustainability_improvements(material_analysis),
        performance_optimizations: suggest_performance_optimizations(material_analysis)
      }
      
      # Context-aware recommendations using AI
      contextual_recommendations = @llm_manager.process_request(
        "Generate contextual design recommendations based on material analysis and design context",
        context: {
          material_analysis: material_analysis,
          design_context: design_context,
          base_recommendations: recommendations
        }
      )
      
      recommendations[:contextual_ai_recommendations] = contextual_recommendations
      recommendations
    end

    # Optimize material selection for specific design requirements
    def optimize_material_selection(requirements)
      puts "⚡ Optimizing material selection for requirements: #{requirements.keys.join(', ')}"
      
      # Search vector database for similar requirements
      similar_cases = search_similar_requirements(requirements)
      
      # Score materials against requirements
      material_scores = score_materials_against_requirements(requirements)
      
      # Generate optimized selection
      optimization_result = {
        recommended_materials: material_scores.first(5),
        alternative_options: material_scores[5..9] || [],
        similar_case_studies: similar_cases,
        optimization_reasoning: generate_optimization_reasoning(requirements, material_scores),
        estimated_performance: estimate_performance_metrics(material_scores.first, requirements)
      }
      
      puts "🎯 Material selection optimized with #{optimization_result[:recommended_materials].size} primary recommendations"
      optimization_result
    end

    # Analyze design trends and material usage patterns
    def analyze_design_trends(time_period = 'recent')
      puts "📈 Analyzing design trends for period: #{time_period}"
      
      # Scrape trend data from design platforms
      trend_sources = [
        'https://materialdesign.io',
        'https://dribbble.com/tags/material_design',
        'https://behance.net/search/projects?search=material%20design'
      ]
      
      trend_data = []
      trend_sources.each do |source|
        begin
          scraped_trends = @scraper.scrape_url(source, {
            extract_design_elements: true,
            extract_color_palettes: true,
            extract_material_usage: true
          })
          trend_data.concat(scraped_trends)
        rescue StandardError => e
          puts "⚠️  Failed to scrape #{source}: #{e.message}"
        end
      end
      
      # Analyze trends using AI
      trend_analysis = @llm_manager.process_request(
        "Analyze material design trends from scraped data",
        context: { trend_data: trend_data, time_period: time_period }
      )
      
      {
        time_period: time_period,
        data_sources: trend_sources.size,
        scraped_samples: trend_data.size,
        trend_analysis: trend_analysis,
        key_patterns: extract_key_patterns(trend_data),
        emerging_materials: identify_emerging_materials(trend_data),
        color_trends: analyze_color_trends(trend_data)
      }
    end

    # Generate material library with comprehensive data
    def build_material_library
      puts "📚 Building comprehensive material library"
      
      # Define material categories to research
      material_categories = [
        'metals', 'plastics', 'ceramics', 'composites', 'textiles',
        'glass', 'wood', 'concrete', 'smart_materials', 'bio_materials'
      ]
      
      library = {}
      
      material_categories.each do |category|
        puts "🔍 Researching #{category} materials"
        
        # Scrape data for this category
        category_data = scrape_material_data("#{category} materials properties specifications")
        
        # Analyze each material in the category
        analyzed_materials = category_data.map do |material_data|
          analyze_material(material_data)
        end
        
        library[category] = {
          count: analyzed_materials.size,
          materials: analyzed_materials,
          category_insights: generate_category_insights(analyzed_materials)
        }
      end
      
      @material_database = library
      
      puts "✅ Material library built with #{library.values.sum { |c| c[:count] }} materials"
      library
    end

    # Export material analysis data
    def export_analysis_data(format = :json)
      case format
      when :json
        export_to_json
      when :csv
        export_to_csv
      when :yaml
        export_to_yaml
      else
        raise "Unsupported export format: #{format}"
      end
    end

    private

    # Load design patterns from knowledge base
    def load_design_patterns
      {
        material_design: {
          elevation: [0, 1, 2, 3, 4, 6, 8, 9, 12, 16, 24],
          colors: ['primary', 'secondary', 'surface', 'background', 'error'],
          typography: ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'subtitle1', 'subtitle2', 'body1', 'body2', 'button', 'caption', 'overline']
        },
        sustainability: {
          recyclable: true,
          biodegradable: false,
          renewable_source: false,
          low_carbon_footprint: false
        },
        performance: {
          durability: 'high',
          flexibility: 'medium',
          thermal_resistance: 'high',
          chemical_resistance: 'medium'
        }
      }
    end

    # Generate analysis key for caching
    def generate_analysis_key(material_data)
      Digest::SHA256.hexdigest(material_data.to_s)[0..15]
    end

    # Analyze basic material properties
    def analyze_basic_properties(material_data)
      {
        density: extract_density(material_data),
        hardness: extract_hardness(material_data),
        melting_point: extract_melting_point(material_data),
        thermal_conductivity: extract_thermal_conductivity(material_data),
        electrical_conductivity: extract_electrical_conductivity(material_data),
        corrosion_resistance: assess_corrosion_resistance(material_data)
      }
    end

    # Assess design compatibility
    def assess_design_compatibility(material_data)
      compatibility_score = 0
      
      # Check against material design principles
      @design_patterns[:material_design].each do |property, values|
        if material_data[property] && values.include?(material_data[property])
          compatibility_score += 20
        end
      end
      
      {
        score: [compatibility_score, 100].min,
        compatible_patterns: find_compatible_patterns(material_data),
        recommended_applications: suggest_applications_from_compatibility(material_data)
      }
    end

    # Calculate sustainability score
    def calculate_sustainability_score(material_data)
      score = 0
      
      score += 25 if material_data[:recyclable]
      score += 20 if material_data[:biodegradable]
      score += 20 if material_data[:renewable_source]
      score += 15 if material_data[:low_carbon_footprint]
      score += 10 if material_data[:locally_sourced]
      score += 10 if material_data[:non_toxic]
      
      {
        total_score: score,
        rating: score_to_rating(score),
        improvement_suggestions: generate_sustainability_improvements(material_data, score)
      }
    end

    # Generate usage recommendations
    def generate_usage_recommendations(material_data)
      recommendations = []
      
      # Based on properties
      if material_data[:high_strength]
        recommendations << "Suitable for structural applications"
      end
      
      if material_data[:flexibility]
        recommendations << "Good for flexible components and joints"
      end
      
      if material_data[:thermal_resistance]
        recommendations << "Excellent for high-temperature environments"
      end
      
      if material_data[:aesthetic_appeal]
        recommendations << "Ideal for visible design elements"
      end
      
      recommendations
    end

    # Analyze color properties
    def analyze_color_properties(material_data)
      return {} unless material_data[:color_data]
      
      {
        primary_colors: extract_primary_colors(material_data[:color_data]),
        color_temperature: calculate_color_temperature(material_data[:color_data]),
        saturation_levels: analyze_saturation(material_data[:color_data]),
        contrast_ratios: calculate_contrast_ratios(material_data[:color_data]),
        accessibility_score: assess_color_accessibility(material_data[:color_data])
      }
    end

    # Analyze texture properties
    def analyze_texture_properties(material_data)
      return {} unless material_data[:texture_data]
      
      {
        surface_roughness: calculate_surface_roughness(material_data[:texture_data]),
        tactile_quality: assess_tactile_quality(material_data[:texture_data]),
        visual_texture: analyze_visual_texture(material_data[:texture_data]),
        grip_characteristics: evaluate_grip(material_data[:texture_data])
      }
    end

    # Calculate performance metrics
    def calculate_performance_metrics(material_data)
      {
        overall_score: calculate_overall_performance_score(material_data),
        strength_to_weight: calculate_strength_to_weight_ratio(material_data),
        cost_effectiveness: assess_cost_effectiveness(material_data),
        longevity_index: calculate_longevity_index(material_data),
        maintenance_requirements: assess_maintenance_needs(material_data)
      }
    end

    # Store analysis in vector database
    def store_analysis_in_vector_db(analysis)
      @weaviate.store_document(
        "material_analysis_#{analysis[:material_id]}",
        analysis.to_json,
        { 
          type: 'material_analysis',
          timestamp: analysis[:timestamp].to_i,
          material_type: analysis[:basic_properties][:type] || 'unknown'
        }
      )
    end

    # Process scraped material data
    def process_scraped_material_data(scraped_data)
      return [] unless scraped_data.is_a?(Array)
      
      scraped_data.map do |item|
        {
          name: extract_material_name(item),
          properties: extract_material_properties(item),
          specifications: extract_specifications(item),
          images: extract_images(item),
          source_url: item[:url],
          scraped_at: Time.now
        }
      end.compact
    end

    # Helper methods for property extraction
    def extract_density(material_data)
      # Extract density from various possible fields
      material_data[:density] || 
      material_data[:properties]&.[](:density) || 
      extract_from_text(material_data[:description], /density.*?(\d+\.?\d*)/i)
    end

    def extract_hardness(material_data)
      material_data[:hardness] || 
      material_data[:properties]&.[](:hardness) || 
      extract_from_text(material_data[:description], /hardness.*?(\d+\.?\d*)/i)
    end

    def extract_melting_point(material_data)
      material_data[:melting_point] || 
      material_data[:properties]&.[](:melting_point) || 
      extract_from_text(material_data[:description], /melting.*?(\d+\.?\d*)/i)
    end

    def extract_thermal_conductivity(material_data)
      material_data[:thermal_conductivity] || 
      material_data[:properties]&.[](:thermal_conductivity) || 
      extract_from_text(material_data[:description], /thermal.*conductivity.*?(\d+\.?\d*)/i)
    end

    def extract_electrical_conductivity(material_data)
      material_data[:electrical_conductivity] || 
      material_data[:properties]&.[](:electrical_conductivity) || 
      extract_from_text(material_data[:description], /electrical.*conductivity.*?(\d+\.?\d*)/i)
    end

    def assess_corrosion_resistance(material_data)
      resistance_indicators = ['corrosion resistant', 'rust proof', 'oxidation resistant']
      description = material_data[:description]&.downcase || ''
      
      resistance_indicators.any? { |indicator| description.include?(indicator) }
    end

    # Extract data from text using regex
    def extract_from_text(text, pattern)
      return nil unless text.is_a?(String)
      
      match = text.match(pattern)
      match ? match[1].to_f : nil
    end

    # Suggest primary applications based on analysis
    def suggest_primary_applications(analysis)
      applications = []
      
      properties = analysis[:basic_properties]
      
      if properties[:high_strength] && properties[:low_density]
        applications << "Aerospace components"
        applications << "Automotive parts"
      end
      
      if properties[:corrosion_resistance]
        applications << "Marine applications"
        applications << "Chemical equipment"
      end
      
      if analysis[:sustainability_score][:total_score] > 70
        applications << "Green building materials"
        applications << "Sustainable packaging"
      end
      
      applications
    end

    # Find compatible design patterns
    def find_compatible_patterns(material_data)
      compatible = []
      
      @design_patterns.each do |pattern_name, pattern_data|
        compatibility = assess_pattern_compatibility(material_data, pattern_data)
        if compatibility > 0.7
          compatible << { name: pattern_name, compatibility: compatibility }
        end
      end
      
      compatible.sort_by { |p| -p[:compatibility] }
    end

    # Assess pattern compatibility
    def assess_pattern_compatibility(material_data, pattern_data)
      # Simple compatibility scoring based on matching properties
      matches = 0
      total = pattern_data.size
      
      pattern_data.each do |key, value|
        if material_data[key] == value
          matches += 1
        end
      end
      
      matches.to_f / total
    end

    # Convert score to rating
    def score_to_rating(score)
      case score
      when 90..100 then 'Excellent'
      when 75..89  then 'Very Good'
      when 60..74  then 'Good'
      when 40..59  then 'Fair'
      when 20..39  then 'Poor'
      else 'Very Poor'
      end
    end

    # Generate sustainability improvements
    def generate_sustainability_improvements(material_data, current_score)
      improvements = []
      
      improvements << "Consider recyclable alternatives" unless material_data[:recyclable]
      improvements << "Look for biodegradable options" unless material_data[:biodegradable]
      improvements << "Source from renewable materials" unless material_data[:renewable_source]
      improvements << "Optimize for lower carbon footprint" unless material_data[:low_carbon_footprint]
      
      improvements
    end

    # Export methods
    def export_to_json
      {
        material_database: @material_database,
        analysis_cache: @analysis_cache,
        exported_at: Time.now
      }.to_json
    end

    def export_to_csv
      # Implement CSV export logic
      "CSV export not yet implemented"
    end

    def export_to_yaml
      # Implement YAML export logic
      "YAML export not yet implemented"
    end

    # Additional helper methods for comprehensive functionality
    def extract_material_name(item)
      item[:title] || item[:name] || item[:text]&.split&.first(3)&.join(' ')
    end

    def extract_material_properties(item)
      # Extract properties from structured data or text
      properties = {}
      
      if item[:specifications]
        item[:specifications].each do |spec|
          key = spec[:property]&.downcase&.to_sym
          value = spec[:value]
          properties[key] = value if key && value
        end
      end
      
      properties
    end

    def extract_specifications(item)
      item[:specifications] || item[:technical_data] || {}
    end

    def extract_images(item)
      item[:images] || []
    end

    # Additional analysis methods for completeness
    def search_similar_requirements(requirements)
      # Search vector database for similar requirements
      query = requirements.map { |k, v| "#{k}: #{v}" }.join(' ')
      @weaviate.search(query, limit: 5)
    end

    def score_materials_against_requirements(requirements)
      # Score materials in database against requirements
      scored_materials = []
      
      @material_database.each do |category, data|
        data[:materials].each do |material|
          score = calculate_requirement_match_score(material, requirements)
          scored_materials << { material: material, score: score, category: category }
        end
      end
      
      scored_materials.sort_by { |sm| -sm[:score] }
    end

    def calculate_requirement_match_score(material, requirements)
      # Calculate how well a material matches requirements
      total_score = 0
      requirements.each do |req_key, req_value|
        material_value = material.dig(:basic_properties, req_key) || 
                        material.dig(:performance_metrics, req_key)
        
        if material_value
          # Simple scoring - can be enhanced with more sophisticated matching
          if material_value.to_s.downcase.include?(req_value.to_s.downcase)
            total_score += 10
          end
        end
      end
      total_score
    end

    def generate_optimization_reasoning(requirements, material_scores)
      top_material = material_scores.first
      "Selected based on #{requirements.size} requirements. Top material scored #{top_material[:score]} points with excellent compatibility for #{top_material[:category]} category applications."
    end

    def estimate_performance_metrics(top_material, requirements)
      {
        expected_durability: 'high',
        compatibility_score: top_material[:score],
        estimated_lifespan: '10+ years',
        maintenance_level: 'medium'
      }
    end

    # Additional helper methods for trend analysis
    def extract_key_patterns(trend_data)
      # Extract key patterns from trend data
      patterns = Hash.new(0)
      
      trend_data.each do |item|
        # Simple pattern extraction - can be enhanced
        if item[:colors]
          item[:colors].each { |color| patterns[color] += 1 }
        end
        
        if item[:materials]
          item[:materials].each { |material| patterns[material] += 1 }
        end
      end
      
      patterns.sort_by { |_, count| -count }.first(10).to_h
    end

    def identify_emerging_materials(trend_data)
      # Identify emerging materials from trend data
      recent_materials = []
      
      trend_data.each do |item|
        if item[:date] && item[:date] > Time.now - (30 * 24 * 3600) # Last 30 days
          recent_materials.concat(item[:materials] || [])
        end
      end
      
      recent_materials.uniq.first(10)
    end

    def analyze_color_trends(trend_data)
      # Analyze color trends from trend data
      color_frequency = Hash.new(0)
      
      trend_data.each do |item|
        if item[:colors]
          item[:colors].each { |color| color_frequency[color] += 1 }
        end
      end
      
      {
        trending_colors: color_frequency.sort_by { |_, count| -count }.first(10).to_h,
        color_diversity: color_frequency.keys.size,
        dominant_palette: color_frequency.sort_by { |_, count| -count }.first(5).map(&:first)
      }
    end

    def generate_category_insights(analyzed_materials)
      return {} if analyzed_materials.empty?
      
      {
        average_sustainability: analyzed_materials.sum { |m| m[:sustainability_score][:total_score] } / analyzed_materials.size,
        common_applications: analyzed_materials.flat_map { |m| m[:usage_recommendations] }.uniq,
        performance_range: {
          min: analyzed_materials.min_by { |m| m[:performance_metrics][:overall_score] }[:performance_metrics][:overall_score],
          max: analyzed_materials.max_by { |m| m[:performance_metrics][:overall_score] }[:performance_metrics][:overall_score]
        }
      }
    end

    # Color and texture analysis helpers
    def extract_primary_colors(color_data)
      # Extract primary colors from color data
      color_data[:dominant_colors] || []
    end

    def calculate_color_temperature(color_data)
      # Calculate color temperature
      color_data[:temperature] || 'neutral'
    end

    def analyze_saturation(color_data)
      # Analyze saturation levels
      color_data[:saturation] || 'medium'
    end

    def calculate_contrast_ratios(color_data)
      # Calculate contrast ratios
      color_data[:contrast_ratio] || 4.5
    end

    def assess_color_accessibility(color_data)
      # Assess color accessibility
      contrast = calculate_contrast_ratios(color_data)
      contrast >= 4.5 ? 'AA compliant' : 'needs improvement'
    end

    def calculate_surface_roughness(texture_data)
      texture_data[:roughness] || 'smooth'
    end

    def assess_tactile_quality(texture_data)
      texture_data[:tactile] || 'pleasant'
    end

    def analyze_visual_texture(texture_data)
      texture_data[:visual_appeal] || 'good'
    end

    def evaluate_grip(texture_data)
      texture_data[:grip] || 'adequate'
    end

    # Performance calculation helpers
    def calculate_overall_performance_score(material_data)
      # Calculate overall performance score
      scores = []
      scores << (material_data[:strength] || 5) * 2
      scores << (material_data[:durability] || 5) * 2
      scores << (material_data[:cost_effectiveness] || 5) * 1.5
      scores << (material_data[:sustainability] || 5) * 1.5
      
      scores.sum / 7.0
    end

    def calculate_strength_to_weight_ratio(material_data)
      strength = material_data[:strength] || 1
      weight = material_data[:density] || 1
      (strength / weight).round(2)
    end

    def assess_cost_effectiveness(material_data)
      cost = material_data[:cost] || 50
      performance = material_data[:performance] || 50
      
      case (performance / cost)
      when 0..0.5 then 'poor'
      when 0.5..1.0 then 'fair'
      when 1.0..2.0 then 'good'
      else 'excellent'
      end
    end

    def calculate_longevity_index(material_data)
      factors = [
        material_data[:durability] || 5,
        material_data[:corrosion_resistance] ? 8 : 3,
        material_data[:thermal_resistance] || 5,
        material_data[:uv_resistance] || 5
      ]
      
      (factors.sum / factors.size.to_f).round(1)
    end

    def assess_maintenance_needs(material_data)
      maintenance_indicators = [
        material_data[:self_cleaning] ? -2 : 0,
        material_data[:corrosion_resistant] ? -1 : 1,
        material_data[:scratch_resistant] ? -1 : 1,
        material_data[:stain_resistant] ? -1 : 1
      ]
      
      maintenance_score = maintenance_indicators.sum
      
      case maintenance_score
      when -4..-2 then 'very low'
      when -1..1 then 'low'
      when 2..3 then 'medium'
      else 'high'
      end
    end
  end
end