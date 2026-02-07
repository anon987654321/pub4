require 'net/http'
require 'uri'
require 'json'

module MASTER
  class LLM
    API_URL = 'https://openrouter.ai/api/v1/chat/completions'
    
    def initialize
      @api_key = load_api_key
    end

    def analyze(ast, language)
      prompt = "Analyze this #{language} code for refactoring opportunities: #{ast.inspect[0..1000]}"
      response = call_api(prompt)
      
      if response['error']
        { risk: 'high', suggestions: [], error: response['error'] }
      else
        content = response.dig('choices', 0, 'message', 'content')
        # Simple parse (expand for JSON)
        { risk: 'low', suggestions: [{ type: 'extract_method', range: [1,5], description: 'Extract long method' }], content: content }
      end
    rescue => e
      { risk: 'high', suggestions: [], error: e.message }
    end

    private

    def load_api_key
      ENV['OPENROUTER_API_KEY'] || File.read(File.expand_path('~/.master_config')).match(/openrouter_api_key: "(.*)"/)&.captures&.first || ''
    end

    def call_api(prompt)
      return { 'error' => 'No API key' } unless @api_key
      
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = { model: 'anthropic/claude-3.5-sonnet', messages: [{ role: 'user', content: prompt }], temperature: 0.1 }.to_json

      resp = http.request(request)
      resp.code == '200' ? JSON.parse(resp.body) : { 'error' => "API error: #{resp.code}" }
    end
  end
end
