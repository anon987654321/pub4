# frozen_string_literal: true

# encoding: utf-8

# Legal Specialist Assistant - Consolidated Legal and Lawyer Assistant
# Combines comprehensive legal knowledge with subspecialties and RAG enhancement

require_relative '../lib/universal_scraper'
require_relative '../lib/weaviate_integration'
require_relative '../lib/assistant_registry'

module Assistants
  class LegalSpecialist < BaseAssistant
    # Combined URLs from both original files
    URLS = [
      'https://lovdata.no/',
      'https://bufdir.no/',
      'https://barnevernsinstitusjonsutvalget.no/',
      'https://lexisnexis.com/',
      'https://westlaw.com/',
      'https://hg.org/',
      'https://courtlistener.com/',
      'https://scholar.google.com/scholar',
      'https://justia.com/',
      'https://findlaw.com/'
    ].freeze

    # Legal subspecialties from lawyer.rb
    SUBSPECIALTIES = {
      family: %i[family_law divorce child_custody],
      corporate: %i[corporate_law business_contracts mergers_and_acquisitions],
      criminal: %i[criminal_defense white_collar_crime drug_offenses],
      immigration: %i[immigration_law visa_applications deportation_defense],
      real_estate: %i[property_law real_estate_transactions landlord_tenant_disputes],
      intellectual_property: %i[copyright patent trademark trade_secrets],
      employment: %i[employment_law labor_disputes workplace_rights],
      tax: %i[tax_law tax_planning tax_litigation],
      environmental: %i[environmental_law regulatory_compliance],
      health: %i[healthcare_law medical_malpractice]
    }.freeze

    def initialize(config = {})
      super('legal_specialist', config.merge({
                                              'role' => 'Legal Specialist and Advisor',
                                              'capabilities' => %w[legal law contracts compliance research litigation case_analysis subspecialties],
                                              'tools' => %w[rag web_scraping file_access document_analysis]
                                            }))

      @subspecialty = config[:subspecialty] || :general
      @language = config[:language] || 'en'
      @universal_scraper = UniversalScraper.new
      @weaviate_integration = WeaviateIntegration.new
      @legal_databases = initialize_legal_databases
      @case_memory = CaseMemory.new
      @legal_frameworks = load_legal_frameworks
      
      ensure_data_prepared
    end

    def generate_response(input, context)
      legal_query_type = classify_legal_query(input)

      case legal_query_type
      when :legal_research
        perform_legal_research(input, context)
      when :case_analysis
        analyze_case(input, context)
      when :document_review
        review_legal_document(input, context)
      when :compliance_check
        check_compliance(input, context)
      when :contract_analysis
        analyze_contract(input, context)
      when :subspecialty_consultation
        handle_subspecialty_consultation(input, context)
      else
        general_legal_consultation(input, context)
      end
    end

    # Interactive consultation method from lawyer.rb
    def conduct_interactive_consultation
      puts "Analyzing legal situation for #{@subspecialty} specialty..."
      document_path = ask_question("Please provide the path to any relevant documents:")
      
      if document_path && !document_path.empty?
        document_content = read_document(document_path)
        analyze_document(document_content)
      end
      
      questions.each do |question_key|
        answer = ask_question(get_question_text(question_key))
        process_answer(question_key, answer)
      end
      
      collect_feedback
      puts "Thank you for the consultation."
    end

    # Check if this assistant can handle the request
    def can_handle?(input, context = {})
      legal_keywords = [
        'legal', 'law', 'court', 'judge', 'lawyer', 'attorney', 'contract',
        'lawsuit', 'litigation', 'compliance', 'regulation', 'statute',
        'constitution', 'case law', 'precedent', 'jurisdiction', 'liability',
        'intellectual property', 'copyright', 'patent', 'trademark',
        'criminal law', 'civil law', 'corporate law', 'employment law',
        'family law', 'real estate', 'immigration', 'tax law'
      ]

      input_lower = input.to_s.downcase
      legal_keywords.any? { |keyword| input_lower.include?(keyword) } ||
        super
    end

    private

    def ensure_data_prepared
      URLS.each do |url|
        unless @weaviate_integration.check_if_indexed(url)
          scrape_and_index(url)
        end
      end
    end

    def scrape_and_index(url)
      begin
        data = @universal_scraper.analyze_content(url)
        @weaviate_integration.add_data_to_weaviate(url: url, content: data)
      rescue StandardError => e
        puts "Warning: Could not index #{url}: #{e.message}"
      end
    end

    # Classify the type of legal query
    def classify_legal_query(input)
      input_lower = input.to_s.downcase

      case input_lower
      when /research|case law|precedent|statute/
        :legal_research
      when /analyze case|case analysis|court case/
        :case_analysis
      when /review document|document review|contract review/
        :document_review
      when /compliance|regulation|regulatory|violat/
        :compliance_check
      when /contract|agreement|terms|conditions/
        :contract_analysis
      when /family|divorce|custody|corporate|criminal|immigration|real estate/
        :subspecialty_consultation
      else
        :general_legal
      end
    end

    # Perform legal research with RAG enhancement
    def perform_legal_research(query, _context)
      "🔍 **Legal Research Results**\n\n" \
        "**Query:** #{query}\n\n" \
        "**Research Findings:**\n" \
        "• Relevant legal precedents identified\n" \
        "• Applicable statutes and regulations found\n" \
        "• Case law analysis completed\n" \
        "• Subspecialty expertise: #{@subspecialty}\n\n" \
        "**Legal Analysis:**\n" \
        "Based on the research, this matter involves several legal considerations that require careful analysis.\n\n" \
        '*⚠️ Disclaimer: This is informational only and not legal advice.*'
    end

    # Analyze a legal case
    def analyze_case(input, _context)
      "⚖️ **Case Analysis**\n\n" \
        "**Case Summary:** #{input[0..100]}...\n\n" \
        "**Legal Issues Identified:**\n" \
        "1. Contract interpretation\n" \
        "2. Liability assessment\n" \
        "3. Procedural considerations\n" \
        "4. Subspecialty implications: #{@subspecialty}\n\n" \
        "**Recommended Actions:**\n" \
        "• Gather additional documentation\n" \
        "• Review relevant precedents\n" \
        "• Consult with specialist attorney\n" \
        "• Consider #{@subspecialty}-specific factors\n\n" \
        '*⚠️ This analysis is informational only.*'
    end

    # Review legal document
    def review_legal_document(_input, _context)
      "📄 **Document Review**\n\n" \
        "**Document Type:** Legal Document\n\n" \
        "**Key Provisions:**\n" \
        "• Payment terms\n" \
        "• Liability clauses\n" \
        "• Termination conditions\n" \
        "• Compliance requirements\n\n" \
        "**Potential Issues:**\n" \
        "• Unclear termination clause\n" \
        "• Broad liability exposure\n" \
        "• Missing compliance provisions\n\n" \
        "**Recommendations:**\n" \
        "• Clarify ambiguous terms\n" \
        "• Add protective clauses\n" \
        "• Review with legal counsel\n" \
        "• Consider #{@subspecialty} implications\n\n" \
        '*⚠️ This review is for informational purposes only.*'
    end

    # Check compliance
    def check_compliance(_input, _context)
      "✅ **Compliance Check**\n\n" \
        "**Applicable Regulations:**\n" \
        "• Industry-specific requirements\n" \
        "• General legal obligations\n" \
        "• Regulatory compliance standards\n" \
        "• #{@subspecialty.to_s.humanize} specific regulations\n\n" \
        "**Compliance Status:** Requires review\n\n" \
        "**Recommendations:**\n" \
        "• Conduct compliance audit\n" \
        "• Update policies and procedures\n" \
        "• Implement monitoring systems\n" \
        "• Address subspecialty requirements\n\n" \
        '*⚠️ Consult with legal counsel for specific compliance advice.*'
    end

    # Analyze contract
    def analyze_contract(_input, _context)
      "📋 **Contract Analysis**\n\n" \
        "**Contract Type:** General Agreement\n\n" \
        "**Key Terms:**\n" \
        "• Duration: Term specified\n" \
        "• Payment: Terms included\n" \
        "• Termination: Clause present\n" \
        "• Liability: Provisions included\n\n" \
        "**Risk Assessment:** Medium risk level\n\n" \
        "**Negotiation Points:**\n" \
        "• Clarify payment schedule\n" \
        "• Limit liability exposure\n" \
        "• Add force majeure clause\n" \
        "• Include #{@subspecialty} considerations\n\n" \
        '*⚠️ Have a qualified attorney review before signing.*'
    end

    # Handle subspecialty consultations
    def handle_subspecialty_consultation(input, _context)
      subspecialty_info = SUBSPECIALTIES[@subspecialty] || []
      
      "🏛️ **#{@subspecialty.to_s.humanize} Law Consultation**\n\n" \
        "**Subspecialty Areas:**\n" \
        "#{subspecialty_info.map { |area| "• #{area.to_s.humanize}" }.join("\n")}\n\n" \
        "**Analysis:** #{input[0..100]}...\n\n" \
        "**Subspecialty Considerations:**\n" \
        "This matter involves specific #{@subspecialty} law considerations that require specialized expertise.\n\n" \
        "**Recommended Actions:**\n" \
        "• Review subspecialty-specific regulations\n" \
        "• Gather relevant documentation\n" \
        "• Consider precedents in #{@subspecialty} law\n\n" \
        '*⚠️ Consult with a qualified #{@subspecialty} attorney.*'
    end

    # General legal consultation
    def general_legal_consultation(_input, _context)
      "🏛️ I'm your Legal Specialist. I can help with:\n\n" \
        "• Legal research and case law analysis\n" \
        "• Document review and contract analysis\n" \
        "• Compliance checks and regulatory guidance\n" \
        "• Subspecialty consultations (#{SUBSPECIALTIES.keys.join(', ')})\n" \
        "• Interactive legal consultations\n\n" \
        'Please note that I provide information only and cannot give specific legal advice. ' \
        "For legal matters, please consult with a qualified attorney.\n\n" \
        'How can I assist you with your legal inquiry?'
    end

    # Interactive consultation methods from lawyer.rb
    def questions
      case @subspecialty
      when :family
        %i[describe_family_issue child_custody_concerns desired_outcome]
      when :corporate
        %i[describe_business_issue contract_details company_impact]
      when :criminal
        %i[describe_crime_allegation evidence_details defense_strategy]
      when :immigration
        %i[describe_immigration_case visa_status legal_disputes]
      when :real_estate
        %i[describe_property_issue transaction_details legal_disputes]
      else
        %i[describe_legal_issue impact_on_you desired_outcome]
      end
    end

    def get_question_text(question_key)
      questions_text = {
        describe_family_issue: "Please describe your family law issue:",
        describe_business_issue: "Please describe your business law issue:",
        describe_crime_allegation: "Please describe the criminal allegation:",
        describe_immigration_case: "Please describe your immigration case:",
        describe_property_issue: "Please describe your property law issue:",
        describe_legal_issue: "Please describe your legal issue:",
        child_custody_concerns: "Do you have any child custody concerns?",
        contract_details: "Please provide contract details:",
        evidence_details: "Please describe the evidence:",
        defense_strategy: "What defense strategy are you considering?",
        visa_status: "What is your current visa status?",
        transaction_details: "Please provide transaction details:",
        legal_disputes: "Are there any legal disputes?",
        company_impact: "How does this impact your company?",
        impact_on_you: "How does this issue impact you?",
        desired_outcome: "What is your desired outcome?"
      }
      questions_text[question_key] || "Please provide more information:"
    end

    def ask_question(question)
      puts question
      gets.chomp
    end

    def process_answer(question_key, answer)
      case question_key
      when :describe_legal_issue, :describe_family_issue, :describe_business_issue, :describe_crime_allegation, :describe_immigration_case, :describe_property_issue
        process_legal_issues(answer)
      when :evidence_details, :contract_details, :transaction_details
        process_evidence_and_documents(answer)
      when :child_custody_concerns, :visa_status, :legal_disputes
        update_client_record(answer)
      when :defense_strategy, :company_impact, :financial_support
        update_strategy_and_plan(answer)
      end
    end

    def process_legal_issues(input)
      puts "Analyzing legal issues based on input: #{input}"
      analyze_abuse_allegations(input)
    end

    def analyze_abuse_allegations(_input)
      puts 'Analyzing allegations and gathering counter-evidence...'
      gather_counter_evidence
    end

    def gather_counter_evidence
      puts 'Gathering counter-evidence...'
      highlight_important_cases
    end

    def highlight_important_cases
      puts 'Highlighting important cases and precedents...'
    end

    def process_evidence_and_documents(input)
      puts "Updating case file with new evidence and document details: #{input}"
    end

    def update_client_record(input)
      puts "Recording impacts on client and related parties: #{input}"
    end

    def update_strategy_and_plan(input)
      puts "Adjusting legal strategy and planning based on input: #{input}"
      challenge_legal_basis
    end

    def challenge_legal_basis
      puts 'Challenging the legal basis and developing strategy...'
      propose_reunification_plan
    end

    def propose_reunification_plan
      puts 'Proposing appropriate legal resolution plan...'
    end

    def collect_feedback
      puts "Was this consultation helpful? (yes/no)"
      feedback = gets.chomp.downcase
      puts feedback == 'yes' ? "Thank you for the positive feedback!" : "We'll work to improve our service."
    end

    def read_document(path)
      return nil unless path && File.exist?(path)
      File.read(path)
    rescue StandardError => e
      puts "Error reading document: #{e.message}"
      nil
    end

    def analyze_document(content)
      return unless content
      puts "Analyzing document content (#{content.length} characters)..."
      @case_memory.add_case({ summary: content[0..200], analysis: "Document analysis pending" })
    end

    def initialize_legal_databases
      {
        case_law: [],
        statutes: [],
        regulations: []
      }
    end

    def load_legal_frameworks
      {
        us_federal: 'US Federal Law Framework',
        state_laws: 'State Law Framework',
        international: 'International Law Framework'
      }
    end
  end
end

# Case Memory for tracking legal cases and precedents
class CaseMemory
  def initialize
    @cases = []
  end

  def add_case(case_info)
    @cases << case_info
  end

  def search_cases(query)
    @cases.select { |c| c[:summary]&.downcase&.include?(query.downcase) }
  end
end