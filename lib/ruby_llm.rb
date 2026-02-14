# frozen_string_literal: true

# Minimal RubyLLM stub for refactoring purposes
# In a real implementation, this would be provided by the ruby_llm gem

module RubyLLM
  class << self
    attr_accessor :openrouter_api_key
    
    def configure
      yield self if block_given?
    end
    
    # Returns array of model metadata
    # In real implementation, this would come from the gem's built-in registry
    def models
      @models ||= load_default_models
    end
    
    # Set custom models (for testing or override)
    def models=(model_list)
      @models = model_list
    end
    
    def chat(model:)
      Chat.new(model)
    end
    
    private
    
    def load_default_models
      # Load from YAML if available, otherwise return empty array
      # Real implementation would have 800+ built-in models
      models_file = File.join(__dir__, "..", "MASTER2", "data", "models.yml")
      if File.exist?(models_file)
        require "yaml"
        YAML.safe_load_file(models_file, symbolize_names: true) || []
      else
        []
      end
    end
  end
  
  class Chat
    attr_reader :model, :thinking_effort, :json_schema, :params
    
    def initialize(model)
      @model = model
      @thinking_effort = nil
      @json_schema = nil
      @params = {}
    end
    
    def with_thinking(effort)
      @thinking_effort = effort
      self
    end
    
    def with_json_schema(schema)
      @json_schema = schema
      self
    end
    
    def with_params(params)
      @params = params
      self
    end
    
    def ask(content, &block)
      # Stub implementation - would make actual API call in real gem
      # Always return valid numeric values for consistency
      Response.new(
        content: "Stub response",
        input_tokens: 100,
        output_tokens: 50,
        cost: 0.001,
        reasoning: nil
      )
    end
  end
  
  class Response
    attr_reader :content, :input_tokens, :output_tokens, :cost, :reasoning
    
    def initialize(content:, input_tokens:, output_tokens:, cost:, reasoning: nil)
      @content = content
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @cost = cost
      @reasoning = reasoning
    end
  end
end
