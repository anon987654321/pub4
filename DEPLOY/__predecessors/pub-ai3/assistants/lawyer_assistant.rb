# frozen_string_literal: true

require 'yaml'
require 'i18n'
require_relative '../lib/universal_scraper'
require_relative '../lib/rag_engine'

# Norwegian Legal Assistant with Lovdata.no integration
# Specializes in 10 Norwegian legal areas with comprehensive legal research capabilities
class LawyerAssistant
  attr_reader :name, :role, :capabilities, :specializations, :lovdata_scraper, :rag_engine, :cognitive_monitor

  # 10 Norwegian Legal Specializations
  LEGAL_SPECIALIZATIONS = {
    familierett: {
      name: 'Familierett',
      description: 'Family Law - Marriage, divorce, child custody, inheritance',
      keywords: %w[familie skilsmisse foreldrerett barnebidrag arv ektepakt samboer],
      lovdata_sections: %w[ekteskapsloven barnelova arvelova vergemålslova]
    },
    straffrett: {
      name: 'Straffrett',
      description: 'Criminal Law - Criminal cases, procedures, penalties',
      keywords: %w[straffesak domstol anklage forsvar straff bot fengsel],
      lovdata_sections: %w[straffeloven straffeprosessloven]
    },
    sivilrett: {
      name: 'Sivilrett',
      description: 'Civil Law - Contracts, property, obligations, tort',
      keywords: %w[kontrakt eiendom erstatning avtale mislighold kjøp salg],
      lovdata_sections: %w[avtalelov kjøpsloven skadeserstatningsloven]
    },
    forvaltningsrett: {
      name: 'Forvaltningsrett',
      description: 'Administrative Law - Government decisions, appeals, public administration',
      keywords: %w[forvaltning vedtak klage offentlig myndighet fylkesmann],
      lovdata_sections: %w[forvaltningsloven offentlighetsloven]
    },
    grunnlovsrett: {
      name: 'Grunnlovsrett',
      description: 'Constitutional Law - Constitutional principles, human rights',
      keywords: %w[grunnlov menneskerettigheter demokrati ytringsfrihet religionsfrihet],
      lovdata_sections: %w[grunnloven menneskerettsloven]
    },
    selskapsrett: {
      name: 'Selskapsrett',
      description: 'Corporate Law - Company formation, governance, mergers',
      keywords: %w[selskap aksjer styre AS aksjeselskap fusjon oppkjøp],
      lovdata_sections: %w[aksjeloven allmennaksjeloven]
    },
    eiendomsrett: {
      name: 'Eiendomsrett',
      description: 'Property Law - Real estate, land rights, registration',
      keywords: %w[eiendom grunn bygning tinglysing servitutt naboforhold],
      lovdata_sections: %w[jordlova eierseksjonsloven bustadbyggjelova]
    },
    arbeidsrett: {
      name: 'Arbeidsrett',
      description: 'Employment Law - Worker rights, labor relations, unions',
      keywords: %w[arbeid ansatt oppsigelse tariffavtale fagforening permittering],
      lovdata_sections: %w[arbeidsmiljøloven ferieloven]
    },
    skatterett: {
      name: 'Skatterett',
      description: 'Tax Law - Tax obligations, planning, disputes',
      keywords: %w[skatt avgift skattemelding mva formuesskatt arveavgift],
      lovdata_sections: %w[skatteloven merverdiavgiftsloven]
    },
    utlendingsrett: {
      name: 'Utlendingsrett',
      description: 'Immigration Law - Visa, residence permits, citizenship',
      keywords: %w[innvandring opphold statsborgerskap asyl arbeidsvilkår utvisning],
      lovdata_sections: %w[utlendingsloven statsborgerloven]
    }
  }.freeze

  def initialize(cognitive_monitor = nil)
    @name = 'Norwegian Legal Specialist'
    @role = 'Norwegian legal expert with Lovdata.no integration'
    @capabilities = [
      'norwegian_law', 'legal_research', 'document_analysis',
      'precedent_search', 'compliance_checking', 'lovdata_integration'
    ]
    @specializations = LEGAL_SPECIALIZATIONS.keys
    @cognitive_monitor = cognitive_monitor
    
    # Initialize components
    initialize_lovdata_scraper
    initialize_rag_engine
    
    # Load configuration
    load_config
  end

  # Main interface for handling legal queries
  def respond(query, context: {})
    # Detect Norwegian legal specialization from query
    specialization = detect_specialization(query)
    
    puts I18n.t('ai3.legal.norwegian.specialization_selected', area: specialization[:name])
    
    # Search Lovdata for relevant legal information
    lovdata_results = search_lovdata(query, specialization)
    
    # Search existing legal knowledge base
    rag_results = @rag_engine.search(query, collection: 'norwegian_legal')
    
    # Find relevant precedents
    precedents = find_precedents(query, specialization)
    
    # Generate comprehensive legal response
    generate_legal_response(query, specialization, lovdata_results, rag_results, precedents)
  end

  # Norwegian legal document analysis
  def analyze_document(document_text, document_type = :unknown)
    puts I18n.t('ai3.legal.norwegian.document_analyzed')
    
    # Detect legal areas covered in document
    relevant_areas = detect_legal_areas(document_text)
    
    # Extract key legal concepts
    legal_concepts = extract_legal_concepts(document_text)
    
    # Check compliance with Norwegian law
    compliance_status = check_compliance(document_text, relevant_areas)
    
    {
      legal_areas: relevant_areas,
      legal_concepts: legal_concepts,
      compliance: compliance_status,
      recommendations: generate_compliance_recommendations(compliance_status)
    }
  end

  # Search Høyesterett and lower court decisions
  def search_precedents(query, court_level = :all)
    courts = case court_level
             when :høyesterett
               ['Høyesterett']
             when :lagmannsrett
               ['Lagmannsrett', 'Høyesterett']
             when :tingrett
               ['Tingrett', 'Lagmannsrett', 'Høyesterett']
             else
               ['Tingrett', 'Lagmannsrett', 'Høyesterett']
             end
    
    results = []
    courts.each do |court|
      court_results = search_court_decisions(query, court)
      results.concat(court_results)
    end
    
    puts I18n.t('ai3.legal.norwegian.precedent_found', count: results.size)
    results
  end

  # Norwegian business regulatory compliance checking
  def check_business_compliance(business_data)
    compliance_areas = [
      :company_registration,
      :tax_obligations,
      :employment_law,
      :data_protection,
      :industry_specific_regulations
    ]
    
    compliance_results = {}
    
    compliance_areas.each do |area|
      compliance_results[area] = assess_compliance_area(business_data, area)
    end
    
    overall_status = calculate_overall_compliance(compliance_results)
    puts I18n.t('ai3.legal.norwegian.compliance_check', status: overall_status)
    
    {
      overall_status: overall_status,
      area_results: compliance_results,
      recommendations: generate_business_recommendations(compliance_results)
    }
  end

  # Multi-agent legal research coordination
  def coordinate_legal_research(complex_query)
    return unless @cognitive_monitor
    
    # Assess complexity and cognitive load
    complexity = @cognitive_monitor.assess_complexity(complex_query)
    
    if complexity > 6
      # Break down into smaller research tasks
      subtasks = decompose_legal_query(complex_query)
      
      results = []
      subtasks.each do |subtask|
        result = respond(subtask[:query], context: subtask[:context])
        results << { subtask: subtask, result: result }
      end
      
      # Synthesize results
      synthesize_legal_research(results)
    else
      # Handle as single task
      respond(complex_query)
    end
  end

  private

  def initialize_lovdata_scraper
    @lovdata_scraper = UniversalScraper.new(
      screenshot_dir: 'data/lovdata_screenshots',
      timeout: 45,
      user_agent: 'AI3-Legal-Research-Bot/1.0'
    )
    @lovdata_scraper.set_cognitive_monitor(@cognitive_monitor) if @cognitive_monitor
  end

  def initialize_rag_engine
    @rag_engine = RAGEngine.new(
      db_path: 'data/norwegian_legal_vector_store.db'
    )
    @rag_engine.set_cognitive_monitor(@cognitive_monitor) if @cognitive_monitor
  end

  def load_config
    config_path = File.join(__dir__, '..', 'config', 'config.yml')
    @config = File.exist?(config_path) ? YAML.load_file(config_path) : {}
  end

  def detect_specialization(query)
    # Analyze query to determine most relevant legal specialization
    query_downcase = query.downcase
    
    best_match = nil
    best_score = 0
    
    LEGAL_SPECIALIZATIONS.each do |key, spec|
      score = spec[:keywords].count { |keyword| query_downcase.include?(keyword) }
      if score > best_score
        best_score = score
        best_match = spec
      end
    end
    
    best_match || LEGAL_SPECIALIZATIONS[:sivilrett] # Default to civil law
  end

  def search_lovdata(query, specialization)
    return [] unless lovdata_enabled?
    
    puts I18n.t('ai3.legal.norwegian.searching_lovdata')
    
    # Construct Lovdata search URLs for relevant legal sections
    search_results = []
    
    specialization[:lovdata_sections].each do |section|
      search_url = construct_lovdata_url(query, section)
      
      begin
        result = @lovdata_scraper.scrape(search_url)
        if result[:success]
          processed_result = process_lovdata_content(result, section)
          search_results << processed_result
          
          # Add to RAG for future searches
          add_to_legal_knowledge_base(processed_result)
        end
      rescue => e
        puts "Error scraping Lovdata for #{section}: #{e.message}"
      end
    end
    
    search_results
  end

  def construct_lovdata_url(query, section)
    base_url = @config.dig('norwegian_legal', 'lovdata', 'base_url') || 'https://lovdata.no'
    # Simplified URL construction - in practice, this would use Lovdata's search API
    "#{base_url}/pro#search/#{URI.encode_www_form_component(query)}/#{section}"
  end

  def process_lovdata_content(scraped_result, section)
    {
      section: section,
      title: scraped_result[:title],
      content: scraped_result[:content],
      url: scraped_result[:url],
      timestamp: Time.now,
      source: 'Lovdata.no'
    }
  end

  def find_precedents(query, specialization)
    # Search for relevant court decisions
    search_precedents(query, :all)
  end

  def search_court_decisions(query, court)
    # In practice, this would integrate with court database APIs
    # For now, returning mock structure
    []
  end

  def detect_legal_areas(document_text)
    detected_areas = []
    
    LEGAL_SPECIALIZATIONS.each do |key, spec|
      keyword_matches = spec[:keywords].count { |keyword| document_text.downcase.include?(keyword) }
      detected_areas << key if keyword_matches > 0
    end
    
    detected_areas
  end

  def extract_legal_concepts(document_text)
    # Extract key legal terms, references to laws, etc.
    # This would use NLP in practice
    concepts = []
    
    # Look for law references (simplified)
    law_references = document_text.scan(/(?:§\s*\d+|lov|forskrift|rundskriv)/i)
    concepts.concat(law_references)
    
    concepts.uniq
  end

  def check_compliance(document_text, relevant_areas)
    # Check document against Norwegian legal requirements
    compliance_issues = []
    
    relevant_areas.each do |area|
      area_issues = check_area_compliance(document_text, area)
      compliance_issues.concat(area_issues)
    end
    
    {
      status: compliance_issues.empty? ? :compliant : :issues_found,
      issues: compliance_issues
    }
  end

  def check_area_compliance(document_text, area)
    # Area-specific compliance checking
    # This would contain detailed compliance rules
    []
  end

  def generate_compliance_recommendations(compliance_status)
    return [] if compliance_status[:status] == :compliant
    
    compliance_status[:issues].map do |issue|
      "Consider addressing: #{issue}"
    end
  end

  def assess_compliance_area(business_data, area)
    # Assess specific compliance area for business
    {
      status: :requires_review,
      details: "#{area} compliance assessment needed",
      risk_level: :medium
    }
  end

  def calculate_overall_compliance(area_results)
    risk_levels = area_results.values.map { |result| result[:risk_level] }
    
    if risk_levels.include?(:high)
      :high_risk
    elsif risk_levels.include?(:medium)
      :medium_risk
    else
      :low_risk
    end
  end

  def generate_business_recommendations(compliance_results)
    recommendations = []
    
    compliance_results.each do |area, result|
      if result[:risk_level] != :low
        recommendations << "Review #{area} compliance requirements"
      end
    end
    
    recommendations
  end

  def decompose_legal_query(complex_query)
    # Break complex query into manageable subtasks
    # This would use advanced query analysis
    [
      { query: complex_query, context: {} }
    ]
  end

  def synthesize_legal_research(results)
    # Combine multiple research results into coherent response
    combined_content = results.map { |r| r[:result] }.join("\n\n")
    
    "Comprehensive Legal Analysis:\n\n#{combined_content}"
  end

  def generate_legal_response(query, specialization, lovdata_results, rag_results, precedents)
    response = "Norwegian Legal Analysis - #{specialization[:name]}\n\n"
    
    response += "Query: #{query}\n\n"
    
    unless lovdata_results.empty?
      response += "Lovdata.no Results:\n"
      lovdata_results.each do |result|
        response += "- #{result[:section]}: #{result[:content][0..200]}...\n"
      end
      response += "\n"
    end
    
    unless rag_results.empty?
      response += "Knowledge Base Results:\n"
      rag_results.each do |result|
        response += "- #{result[:content][0..200]}...\n"
      end
      response += "\n"
    end
    
    unless precedents.empty?
      response += "Relevant Precedents:\n"
      precedents.each do |precedent|
        response += "- #{precedent[:title]}: #{precedent[:summary]}\n"
      end
      response += "\n"
    end
    
    response += "Legal Recommendation:\n"
    response += generate_legal_recommendation(query, specialization)
    
    response
  end

  def generate_legal_recommendation(query, specialization)
    "Based on #{specialization[:name]} analysis, consider consulting with a qualified Norwegian lawyer for specific legal advice regarding: #{query}"
  end

  def add_to_legal_knowledge_base(content)
    document = {
      content: content[:content],
      title: content[:title],
      section: content[:section],
      source: content[:source],
      timestamp: content[:timestamp]
    }
    
    @rag_engine.add_document(document, collection: 'norwegian_legal')
  end

  def lovdata_enabled?
    @config.dig('norwegian_legal', 'lovdata', 'enabled') != false
  end
end