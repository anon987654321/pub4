# frozen_string_literal: true

require 'minitest/autorun'
require 'yaml'
require_relative '../ai3'

# AI³ Integration Test Suite
# Tests the complete AI³ platform consolidation including Norwegian legal features
class AI3IntegrationTest < Minitest::Test
  def setup
    @config = load_test_config
    @ai3_cli = AI3CLI.new
  end

  def test_ai3_initialization
    assert_not_nil @ai3_cli, "AI³ CLI should initialize successfully"
    assert_not_nil @ai3_cli.cognitive_orchestrator, "Cognitive orchestrator should be initialized"
    assert_not_nil @ai3_cli.llm_manager, "LLM manager should be initialized"
    assert_not_nil @ai3_cli.session_manager, "Session manager should be initialized"
    assert_not_nil @ai3_cli.rag_engine, "RAG engine should be initialized"
    assert_not_nil @ai3_cli.assistant_registry, "Assistant registry should be initialized"
  end

  def test_configuration_loading
    config = @ai3_cli.config
    
    assert config.key?('ai3'), "Configuration should contain ai3 section"
    assert config.key?('llm'), "Configuration should contain llm section"
    assert config.key?('cognitive'), "Configuration should contain cognitive section"
    assert config.key?('norwegian_legal'), "Configuration should contain norwegian_legal section"
    
    # Test Norwegian legal configuration
    norwegian_config = config['norwegian_legal']
    assert norwegian_config['enabled'], "Norwegian legal should be enabled"
    assert norwegian_config.key?('specializations'), "Should have legal specializations"
    assert_equal 10, norwegian_config['specializations'].size, "Should have 10 legal specializations"
  end

  def test_cognitive_orchestrator_functionality
    orchestrator = @ai3_cli.cognitive_orchestrator
    
    # Test cognitive load management
    initial_load = orchestrator.current_load
    assert initial_load >= 0, "Initial cognitive load should be non-negative"
    assert initial_load <= 7, "Initial cognitive load should not exceed 7±2 limit"
    
    # Test concept addition
    orchestrator.add_concept("test concept", 1.0)
    assert orchestrator.current_load > initial_load, "Adding concept should increase cognitive load"
    
    # Test circuit breaker
    (1..10).each { |i| orchestrator.add_concept("concept #{i}", 1.0) }
    assert orchestrator.cognitive_overload?, "Should detect cognitive overload"
  end

  def test_multi_llm_manager
    llm_manager = @ai3_cli.llm_manager
    
    # Test provider status
    status = llm_manager.provider_status
    assert status.is_a?(Hash), "Provider status should be a hash"
    
    # Test available providers
    expected_providers = [:xai, :anthropic, :openai, :ollama]
    expected_providers.each do |provider|
      assert status.key?(provider), "Should have #{provider} provider configured"
    end
    
    # Test fallback chain
    assert llm_manager.fallback_enabled?, "Fallback should be enabled"
  end

  def test_assistant_registry
    registry = @ai3_cli.assistant_registry
    assistants = registry.list_assistants
    
    # Test minimum number of assistants
    assert assistants.size >= 15, "Should have at least 15 specialized assistants"
    
    # Test key assistants are present
    assistant_names = assistants.map { |a| a[:name] }
    required_assistants = [
      'Norwegian Legal Specialist',
      'Advanced Trading Assistant',
      'Ethical Security Specialist',
      'Medical Research Assistant',
      'Musicians Multi-Agent Orchestra',
      'SEO and Marketing Expert'
    ]
    
    required_assistants.each do |name|
      assert assistant_names.include?(name), "Should include #{name} assistant"
    end
  end

  def test_norwegian_legal_assistant
    registry = @ai3_cli.assistant_registry
    legal_assistant = registry.get_assistant('lawyer')
    
    assert_not_nil legal_assistant, "Norwegian legal assistant should be available"
    assert_equal 'Norwegian Legal Specialist', legal_assistant.name
    
    # Test legal specializations
    specializations = legal_assistant.specializations
    expected_specializations = [
      :familierett, :straffrett, :sivilrett, :forvaltningsrett,
      :grunnlovsrett, :selskapsrett, :eiendomsrett, :arbeidsrett,
      :skatterett, :utlendingsrett
    ]
    
    expected_specializations.each do |spec|
      assert specializations.include?(spec), "Should include #{spec} specialization"
    end
    
    # Test legal capabilities
    capabilities = legal_assistant.capabilities
    expected_capabilities = [
      'norwegian_law', 'legal_research', 'document_analysis',
      'precedent_search', 'compliance_checking', 'lovdata_integration'
    ]
    
    expected_capabilities.each do |capability|
      assert capabilities.include?(capability), "Should include #{capability} capability"
    end
  end

  def test_rag_engine_functionality
    rag_engine = @ai3_cli.rag_engine
    
    # Test document addition
    test_document = {
      content: "This is a test legal document about Norwegian family law.",
      title: "Test Family Law Document",
      source: "test"
    }
    
    result = rag_engine.add_document(test_document, collection: 'test_legal')
    assert result, "Should successfully add document to RAG"
    
    # Test search functionality
    search_results = rag_engine.search("family law", collection: 'test_legal')
    assert search_results.is_a?(Array), "Search should return array of results"
  end

  def test_universal_scraper_integration
    scraper = @ai3_cli.instance_variable_get(:@scraper)
    
    if scraper.nil?
      # Initialize scraper for testing
      scraper = @ai3_cli.send(:initialize_scraper)
      assert_not_nil scraper, "Scraper should initialize successfully"
    end
    
    # Test scraper configuration
    assert scraper.respond_to?(:scrape), "Scraper should have scrape method"
    assert scraper.respond_to?(:set_cognitive_monitor), "Scraper should support cognitive monitoring"
  end

  def test_session_management
    session_manager = @ai3_cli.session_manager
    
    # Test session creation
    session = session_manager.get_session('test_user')
    assert_not_nil session, "Should create session for test user"
    
    # Test session update
    update_data = { test_key: 'test_value' }
    session_manager.update_session('test_user', update_data)
    
    updated_session = session_manager.get_session('test_user')
    assert_equal 'test_value', updated_session[:test_key], "Session should be updated"
    
    # Test cognitive state monitoring
    cognitive_state = session_manager.cognitive_state
    assert cognitive_state.key?(:total_sessions), "Should track total sessions"
    assert cognitive_state.key?(:cognitive_health), "Should track cognitive health"
  end

  def test_localization_support
    # Test English localization
    I18n.locale = :en
    welcome_message = I18n.t('ai3.welcome')
    assert welcome_message.include?('AI³'), "Should have English welcome message"
    
    # Test Norwegian localization
    I18n.locale = :no
    norwegian_welcome = I18n.t('ai3.welcome')
    assert norwegian_welcome.include?('AI³'), "Should have Norwegian welcome message"
    
    # Test legal terms localization
    legal_terms = I18n.t('ai3.legal.norwegian.terms')
    assert legal_terms.key?(:lovdata), "Should have Norwegian legal terms"
    assert legal_terms.key?(:høyesterett), "Should include court terms"
    
    # Reset to English
    I18n.locale = :en
  end

  def test_tools_consolidation
    # Verify tools are consolidated into lib directory
    refute Dir.exist?(File.join(__dir__, '..', 'tools')), "Tools directory should be removed"
    
    # Verify lib contains consolidated tools
    lib_files = Dir.glob(File.join(__dir__, '..', 'lib', '*.rb'))
    lib_basenames = lib_files.map { |f| File.basename(f) }
    
    consolidated_tools = ['universal_scraper.rb', 'filesystem_tool.rb']
    consolidated_tools.each do |tool|
      assert lib_basenames.include?(tool), "#{tool} should be in lib directory"
    end
  end

  def test_swarm_coordination
    registry = @ai3_cli.assistant_registry
    
    # Test multi-agent capability
    musicians_assistant = registry.get_assistant('musicians')
    if musicians_assistant
      assert musicians_assistant.respond_to?(:coordinate_agents), "Musicians assistant should support coordination"
    end
    
    # Test swarm orchestration configuration
    config = @ai3_cli.config
    swarm_config = config.dig('assistants', 'swarm')
    
    if swarm_config
      assert swarm_config['enabled'], "Swarm orchestration should be enabled"
      assert swarm_config['max_concurrent_assistants'], "Should have max concurrent limit"
    end
  end

  def test_error_handling_and_logging
    # Test error handling configuration
    config = @ai3_cli.config
    error_config = config['error_handling']
    
    if error_config
      assert error_config['log_level'], "Should have log level configured"
      assert error_config['circuit_breaker'], "Should have circuit breaker configuration"
    end
    
    # Test log directory creation
    log_dir = File.join(__dir__, '..', 'logs')
    assert Dir.exist?(log_dir), "Logs directory should exist"
  end

  def test_security_configuration
    config = @ai3_cli.config
    security_config = config['security']
    
    if security_config
      # Test OpenBSD integration
      openbsd_config = security_config['openbsd']
      if openbsd_config
        assert openbsd_config.key?('pledge_enabled'), "Should have pledge configuration"
        assert openbsd_config.key?('unveil_enabled'), "Should have unveil configuration"
      end
      
      # Test rate limiting
      rate_limit_config = security_config['rate_limiting']
      if rate_limit_config
        assert rate_limit_config['enabled'], "Rate limiting should be configured"
      end
    end
  end

  def test_performance_caching
    config = @ai3_cli.config
    performance_config = config['performance']
    
    if performance_config
      cache_config = performance_config['cache']
      assert cache_config['enabled'], "Caching should be enabled" if cache_config
      
      lru_config = performance_config['lru_cache']
      assert lru_config['enabled'], "LRU cache should be enabled" if lru_config
    end
  end

  private

  def load_test_config
    config_path = File.join(__dir__, '..', 'config', 'config.yml')
    if File.exist?(config_path)
      YAML.load_file(config_path)
    else
      {}
    end
  end
end

# Additional Test Helper Methods
module AI3TestHelpers
  def create_mock_legal_query
    "What are the requirements for divorce in Norwegian family law?"
  end

  def create_mock_legal_document
    <<~DOCUMENT
      EKTESKAPSKONTRAKT
      
      Undertegnede, [Navn 1] og [Navn 2], som inngår ekteskap den [Dato],
      ønsker å inngå følgende ekteskapskontrakt i henhold til ekteskapsloven § 42.
      
      § 1. Formuesordning
      Ektefellene velger særeie som formuesordning for sitt ekteskap.
      
      § 2. Bolig
      Den felles boligen skal eies som sameie med like deler.
    DOCUMENT
  end

  def mock_lovdata_response
    {
      success: true,
      title: "Ekteskapsloven § 42 - Ekteskapskontrakt",
      content: "Ektefeller kan ved ekteskapskontrakt bestemme at de skal ha særeie...",
      url: "https://lovdata.no/dokument/NL/lov/1991-07-04-47/KAPITTEL_6#KAPITTEL_6",
      timestamp: Time.now
    }
  end
end

# Include test helpers
AI3IntegrationTest.include(AI3TestHelpers)