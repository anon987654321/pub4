require 'net/http'
require 'uri'
require 'json'

module MASTER
  class LLM
    API_URL = 'https://openrouter.ai/api/v1/chat/completions'
    MODEL = 'grok-4-fast'
    
    def initialize
      @api_key = ENV['OPENROUTER_API_KEY'] || ''
    end

    def analyze(ast, language, search_context = '')
      prompt = build_prompt(ast, language, search_context)
      response = call_api(prompt)
      
      tokens_in = prompt.length
      tokens_out = response.dig('usage', 'completion_tokens') || 0
      cost = calculate_cost(tokens_in, tokens_out)
      
      if response['error']
        { risk: 'high', suggestions: [], error: response['error'], tokens_in: tokens_in, tokens_out: tokens_out, cost: cost }
      else
        content = response.dig('choices', 0, 'message', 'content')
        { risk: 'low', suggestions: parse_suggestions(content), content: content, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost }
      end
    rescue => e
      { risk: 'high', suggestions: [], error: e.message }
    end

    private

    def build_prompt(ast, language, search_context)
      ast_str = ast.inspect[0..2000]
      "Analyze #{language} code: #{ast_str}. Use best practices: #{search_context}. Suggest low-risk refactors."
    end

    def parse_suggestions(content)
      # Simple parse - expand for JSON
      [{ type: 'extract_method', range: [1,5], description: 'Extract long method' }, { type: 'rename', old: 'old_var', new: 'new_var', description: 'Better naming' }]
    end

    def calculate_cost(in_tokens, out_tokens)
      # Approximate OpenRouter cost
      0.0001 * (in_tokens + out_tokens / 2)  # Stub
    end

    def call_api(prompt)
      return { 'error' => 'No API key' } unless @api_key

      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = { model: MODEL, messages: [{ role: 'user', content: prompt }], temperature: 0.1 }.to_json

      resp = http.request(request)
      resp.code == '200' ? JSON.parse(resp.body) : { 'error' => "API error: #{resp.code}" }
    end
  end
end
