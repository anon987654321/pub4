require 'net/http'
require 'uri'
require 'json'

module MASTER
  class LLM
    API_URL = ENV['LLM_API_URL'] || 'https://openrouter.ai/api/v1/chat/completions'
    MODEL = ENV['LLM_MODEL'] || 'grok-4-fast'
    
    def initialize
      @api_key = load_api_key
    end

    def analyze(ast, language)
      prompt = build_prompt(ast, language)
      response = call_api(prompt)
      
      if response['error']
        { risk: 'high', suggestions: [], error: response['error'] }
      else
        content = response.dig('choices', 0, 'message', 'content')
        { risk: 'low', suggestions: parse_suggestions(content), content: content }
      end
    rescue => e
      { risk: 'high', suggestions: [], error: e.message }
    end

    private

    def build_prompt(ast, language)
      ast_str = ast.inspect[0..2000]  # Increased, truncate smarter
      "Analyze #{language} code: #{ast_str}. Suggest low-risk refactors."
    end

    def parse_suggestions(content)
      [{ type: 'extract_method', range: [1,5], description: 'Extract long method' }]
    end

    # ... (load_api_key, call_api unchanged)
  end
end
