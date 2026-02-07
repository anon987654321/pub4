module MASTER
  class LLM
    API_URL = 'https://openrouter.ai/api/v1/chat/completions'
    
    def initialize
      @api_key = ENV['OPENROUTER_API_KEY'] || load_api_key
    end
    
    def analyze_code(code, language)
      prompt = build_analysis_prompt(code, language)
      response = call_api(prompt)
      parse_suggestions(response)
    end
    
    private
    
    def load_api_key
      config_path = File.expand_path('~/.master_config')
      return nil unless File.exist?(config_path)
      
      config = JSON.parse(File.read(config_path))
      config['openrouter_api_key']
    end
    
    def build_analysis_prompt(code, language)
      <<~PROMPT
        Analyze this #{language} code for refactoring opportunities.
        Focus on: code smells, performance, readability, maintainability.
        Return JSON with suggestions array containing:
        - type: 'replace', 'extract', 'inline', 'rename'
        - description: human readable explanation
        - from: original code pattern (for replace type)
        - to: improved code pattern (for replace type)
        - risk: 'low', 'medium', 'high'
        
        Code: