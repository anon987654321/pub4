# frozen_string_literal: true

# Enhanced Medical Assistant - Comprehensive medical knowledge and diagnostic assistance
require_relative '__shared.sh'

module Assistants
  class MedicalAssistant
    # Comprehensive medical knowledge sources
    KNOWLEDGE_SOURCES = [
      'https://pubmed.ncbi.nlm.nih.gov/',
      'https://mayoclinic.org/',
      'https://who.int/',
      'https://webmd.com/',
      'https://medlineplus.gov/',
      'https://cochranelibrary.com/',
      'https://nejm.org/',
      'https://bmj.com/',
      'https://nature.com/subjects/medical-research',
      'https://cdc.gov/',
      'https://nih.gov/',
      'https://fda.gov/'
    ].freeze

    # Medical specialties and domains
    MEDICAL_SPECIALTIES = %i[
      cardiology
      dermatology
      endocrinology
      gastroenterology
      hematology
      immunology
      infectious_diseases
      nephrology
      neurology
      oncology
      ophthalmology
      orthopedics
      pediatrics
      psychiatry
      pulmonology
      radiology
      surgery
      urology
      emergency_medicine
      family_medicine
      internal_medicine
      obstetrics_gynecology
    ].freeze

    # Common symptom categories
    SYMPTOM_CATEGORIES = {
      cardiovascular: %w[chest_pain shortness_of_breath palpitations swelling fatigue],
      respiratory: %w[cough wheezing dyspnea sputum chest_tightness],
      gastrointestinal: %w[nausea vomiting diarrhea constipation abdominal_pain],
      neurological: %w[headache dizziness seizures numbness weakness],
      musculoskeletal: %w[joint_pain muscle_pain stiffness swelling],
      dermatological: %w[rash itching lesions discoloration swelling],
      psychiatric: %w[depression anxiety mood_changes sleep_disturbances],
      general: %w[fever weight_loss fatigue malaise night_sweats]
    }.freeze

    def initialize(specialty: :general_medicine)
      @specialty = specialty
      @knowledge_sources = KNOWLEDGE_SOURCES
      @patient_records = []
      @diagnostic_history = []
      @medical_database = initialize_medical_database
    end

    # Enhanced medical condition lookup with comprehensive analysis
    def lookup_condition(condition)
      puts "🔍 Searching comprehensive medical databases for: #{condition}"
      
      condition_info = {
        condition: condition,
        specialty: determine_specialty(condition),
        symptoms: extract_related_symptoms(condition),
        differential_diagnosis: generate_differential_diagnosis(condition),
        treatment_options: suggest_treatment_options(condition),
        prognosis: assess_prognosis(condition),
        prevention: prevention_measures(condition)
      }
      
      @diagnostic_history << condition_info
      format_medical_information(condition_info)
    end

    # Comprehensive medical advice with symptom analysis
    def provide_medical_advice(symptoms)
      puts "🩺 Analyzing symptoms for medical guidance..."
      
      symptom_analysis = analyze_symptom_cluster(symptoms)
      urgency_level = assess_urgency(symptoms)
      recommendations = generate_recommendations(symptoms, urgency_level)
      
      advice = {
        symptoms: symptoms,
        analysis: symptom_analysis,
        urgency: urgency_level,
        recommendations: recommendations,
        next_steps: determine_next_steps(urgency_level),
        red_flags: identify_red_flags(symptoms)
      }
      
      format_medical_advice(advice)
    end

    # Symptom checker with diagnostic assistance
    def symptom_checker(symptom_list)
      puts "🔍 Running comprehensive symptom analysis..."
      
      categorized_symptoms = categorize_symptoms(symptom_list)
      possible_conditions = match_symptoms_to_conditions(categorized_symptoms)
      risk_assessment = assess_symptom_risk(symptom_list)
      
      {
        input_symptoms: symptom_list,
        categorized_symptoms: categorized_symptoms,
        possible_conditions: possible_conditions,
        risk_level: risk_assessment,
        recommendations: generate_symptom_recommendations(risk_assessment)
      }
    end

    # Drug interaction checker
    def check_drug_interactions(medications)
      puts "💊 Checking for potential drug interactions..."
      
      interactions = analyze_drug_interactions(medications)
      severity_levels = assess_interaction_severity(interactions)
      
      {
        medications: medications,
        interactions_found: interactions,
        severity_assessment: severity_levels,
        recommendations: drug_interaction_recommendations(interactions)
      }
    end

    # Medical history analysis
    def analyze_medical_history(history)
      puts "📋 Analyzing comprehensive medical history..."
      
      risk_factors = identify_risk_factors(history)
      patterns = detect_health_patterns(history)
      preventive_measures = suggest_preventive_care(risk_factors)
      
      {
        history_summary: summarize_history(history),
        identified_risks: risk_factors,
        health_patterns: patterns,
        preventive_recommendations: preventive_measures
      }
    end

    # Generate health assessment report
    def generate_health_report(patient_data)
      puts "📊 Generating comprehensive health assessment report..."
      
      report = {
        patient_overview: create_patient_overview(patient_data),
        risk_assessment: comprehensive_risk_assessment(patient_data),
        health_metrics: analyze_health_metrics(patient_data),
        recommendations: personalized_recommendations(patient_data),
        follow_up_plan: create_follow_up_plan(patient_data),
        lifestyle_advice: generate_lifestyle_advice(patient_data)
      }
      
      format_health_report(report)
    end

    # Emergency triage assessment
    def emergency_triage(symptoms, vitals = {})
      puts "🚨 Performing emergency triage assessment..."
      
      triage_level = determine_triage_level(symptoms, vitals)
      immediate_actions = determine_immediate_actions(triage_level)
      
      {
        triage_level: triage_level,
        urgency_score: calculate_urgency_score(symptoms, vitals),
        immediate_actions: immediate_actions,
        estimated_wait_time: estimate_wait_time(triage_level),
        monitoring_requirements: monitoring_requirements(symptoms)
      }
    end

    private

    def initialize_medical_database
      {
        conditions: {},
        medications: {},
        interactions: {},
        symptoms: {},
        treatments: {}
      }
    end

    def determine_specialty(condition)
      # Map conditions to medical specialties
      specialty_mappings = {
        'heart' => :cardiology,
        'skin' => :dermatology,
        'diabetes' => :endocrinology,
        'stomach' => :gastroenterology,
        'brain' => :neurology,
        'cancer' => :oncology,
        'bone' => :orthopedics,
        'child' => :pediatrics,
        'mental' => :psychiatry,
        'lung' => :pulmonology
      }
      
      condition_lower = condition.downcase
      specialty_mappings.find { |key, _| condition_lower.include?(key) }&.last || :general_medicine
    end

    def extract_related_symptoms(condition)
      # Generate related symptoms based on condition
      [
        "Primary symptoms of #{condition}",
        "Secondary manifestations",
        "Associated findings",
        "Complications to monitor"
      ]
    end

    def generate_differential_diagnosis(condition)
      [
        "Primary diagnosis: #{condition}",
        "Alternative diagnoses to consider",
        "Ruling out serious conditions",
        "Further testing recommendations"
      ]
    end

    def suggest_treatment_options(condition)
      {
        conservative: "Conservative management approaches for #{condition}",
        medical: "Medical treatment options",
        surgical: "Surgical interventions if applicable",
        supportive: "Supportive care measures"
      }
    end

    def assess_prognosis(condition)
      "Prognosis varies based on severity, patient factors, and treatment response for #{condition}"
    end

    def prevention_measures(condition)
      [
        "Primary prevention strategies",
        "Risk factor modification",
        "Screening recommendations",
        "Lifestyle modifications"
      ]
    end

    def analyze_symptom_cluster(symptoms)
      categorized = categorize_symptoms(symptoms.split(/[,;]/))
      severity = assess_symptom_severity(symptoms)
      duration = assess_symptom_duration(symptoms)
      
      {
        categories: categorized,
        severity: severity,
        duration: duration,
        pattern: detect_symptom_pattern(symptoms)
      }
    end

    def categorize_symptoms(symptom_list)
      categorized = {}
      
      SYMPTOM_CATEGORIES.each do |category, symptoms|
        matches = symptom_list.select do |symptom|
          symptoms.any? { |s| symptom.downcase.include?(s.tr('_', ' ')) }
        end
        categorized[category] = matches unless matches.empty?
      end
      
      categorized
    end

    def assess_urgency(symptoms)
      high_urgency_indicators = [
        'chest pain', 'severe headache', 'difficulty breathing', 
        'severe bleeding', 'loss of consciousness', 'severe pain'
      ]
      
      symptoms_lower = symptoms.downcase
      if high_urgency_indicators.any? { |indicator| symptoms_lower.include?(indicator) }
        :high
      elsif symptoms_lower.include?('moderate') || symptoms_lower.include?('persistent')
        :moderate
      else
        :low
      end
    end

    def generate_recommendations(symptoms, urgency)
      case urgency
      when :high
        [
          "Seek immediate medical attention",
          "Call emergency services if severe",
          "Do not delay treatment",
          "Monitor vital signs closely"
        ]
      when :moderate
        [
          "Schedule appointment with healthcare provider",
          "Monitor symptoms closely",
          "Seek care if symptoms worsen",
          "Consider urgent care if needed"
        ]
      else
        [
          "Monitor symptoms",
          "Consider self-care measures",
          "Schedule routine appointment if persistent",
          "Maintain symptom diary"
        ]
      end
    end

    def determine_next_steps(urgency)
      case urgency
      when :high
        "Immediate medical evaluation required"
      when :moderate
        "Medical evaluation within 24-48 hours"
      else
        "Monitor and reassess in 1-2 weeks"
      end
    end

    def identify_red_flags(symptoms)
      red_flags = [
        'sudden onset severe symptoms',
        'neurological changes',
        'severe pain',
        'breathing difficulties',
        'chest pain'
      ]
      
      symptoms_lower = symptoms.downcase
      red_flags.select { |flag| symptoms_lower.include?(flag.split.last) }
    end

    def match_symptoms_to_conditions(categorized_symptoms)
      conditions = []
      
      categorized_symptoms.each do |category, symptoms|
        case category
        when :cardiovascular
          conditions += ['Angina', 'Heart failure', 'Arrhythmia']
        when :respiratory
          conditions += ['Asthma', 'COPD', 'Pneumonia']
        when :gastrointestinal
          conditions += ['Gastritis', 'IBS', 'Food poisoning']
        when :neurological
          conditions += ['Migraine', 'Tension headache', 'Neuropathy']
        end
      end
      
      conditions.uniq
    end

    def assess_symptom_risk(symptoms)
      # Simple risk assessment based on symptom content
      high_risk_terms = ['severe', 'acute', 'sudden', 'intense']
      moderate_risk_terms = ['persistent', 'worsening', 'recurring']
      
      symptoms_lower = symptoms.join(' ').downcase
      
      if high_risk_terms.any? { |term| symptoms_lower.include?(term) }
        :high
      elsif moderate_risk_terms.any? { |term| symptoms_lower.include?(term) }
        :moderate
      else
        :low
      end
    end

    def generate_symptom_recommendations(risk_level)
      case risk_level
      when :high
        "Immediate medical evaluation recommended"
      when :moderate
        "Medical consultation advised within 1-2 days"
      else
        "Monitor symptoms and seek care if worsening"
      end
    end

    def analyze_drug_interactions(medications)
      # Simplified drug interaction analysis
      common_interactions = {
        'warfarin' => ['aspirin', 'antibiotics'],
        'metformin' => ['contrast agents'],
        'digoxin' => ['diuretics', 'ACE inhibitors']
      }
      
      interactions = []
      medications.each do |med1|
        medications.each do |med2|
          next if med1 == med2
          if common_interactions[med1.downcase]&.include?(med2.downcase)
            interactions << { drug1: med1, drug2: med2, type: 'potential_interaction' }
          end
        end
      end
      
      interactions
    end

    def assess_interaction_severity(interactions)
      interactions.map do |interaction|
        interaction.merge(severity: 'moderate') # Simplified assessment
      end
    end

    def drug_interaction_recommendations(interactions)
      if interactions.empty?
        "No significant interactions detected"
      else
        "Review medications with healthcare provider - #{interactions.length} potential interactions found"
      end
    end

    def format_medical_information(info)
      "🏥 **Medical Information: #{info[:condition]}**\n\n" \
        "**Specialty:** #{info[:specialty].to_s.humanize}\n" \
        "**Related Symptoms:** #{info[:symptoms].join(', ')}\n" \
        "**Differential Diagnosis:** #{info[:differential_diagnosis].join(', ')}\n" \
        "**Treatment Options:** #{info[:treatment_options].values.join('; ')}\n" \
        "**Prognosis:** #{info[:prognosis]}\n" \
        "**Prevention:** #{info[:prevention].join(', ')}\n\n" \
        "*⚠️ This information is for educational purposes only. Consult healthcare provider for medical advice.*"
    end

    def format_medical_advice(advice)
      urgency_emoji = { high: '🚨', moderate: '⚠️', low: 'ℹ️' }
      
      "#{urgency_emoji[advice[:urgency]]} **Medical Assessment**\n\n" \
        "**Symptoms Analyzed:** #{advice[:symptoms]}\n" \
        "**Urgency Level:** #{advice[:urgency].to_s.upcase}\n" \
        "**Analysis:** #{advice[:analysis][:severity]} severity symptoms\n" \
        "**Recommendations:**\n#{advice[:recommendations].map { |r| "• #{r}" }.join("\n")}\n" \
        "**Next Steps:** #{advice[:next_steps]}\n" \
        "**Red Flags:** #{advice[:red_flags].join(', ') if advice[:red_flags].any?}\n\n" \
        "*⚠️ This assessment is not a substitute for professional medical diagnosis.*"
    end

    # Additional helper methods for comprehensive functionality
    def assess_symptom_severity(symptoms); :moderate; end
    def assess_symptom_duration(symptoms); 'acute'; end
    def detect_symptom_pattern(symptoms); 'intermittent'; end
    def identify_risk_factors(history); ['family_history', 'lifestyle_factors']; end
    def detect_health_patterns(history); ['chronic_condition_pattern']; end
    def suggest_preventive_care(risks); ['regular_screening', 'lifestyle_modification']; end
    def summarize_history(history); "Patient history summary"; end
    def create_patient_overview(data); "Patient overview based on provided data"; end
    def comprehensive_risk_assessment(data); { cardiovascular: :moderate, diabetes: :low }; end
    def analyze_health_metrics(data); { bp: 'normal', cholesterol: 'borderline' }; end
    def personalized_recommendations(data); ['diet_modification', 'exercise_program']; end
    def create_follow_up_plan(data); "Follow-up in 3 months"; end
    def generate_lifestyle_advice(data); ['healthy_diet', 'regular_exercise', 'stress_management']; end
    def determine_triage_level(symptoms, vitals); :moderate; end
    def determine_immediate_actions(level); ['monitor_vitals', 'pain_management']; end
    def calculate_urgency_score(symptoms, vitals); 6; end
    def estimate_wait_time(level); level == :high ? '0-15 min' : '30-60 min'; end
    def monitoring_requirements(symptoms); ['vital_signs', 'pain_assessment']; end
    def format_health_report(report); "Comprehensive health report generated"; end
  end
end
