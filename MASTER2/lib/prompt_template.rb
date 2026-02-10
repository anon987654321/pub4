# frozen_string_literal: true

require "erb"

module MASTER
  # PromptTemplate - Load and render ERB templates for prompts
  module PromptTemplate
    PROMPTS_DIR = File.join(__dir__, "..", "data", "prompts")

    class << self
      # Render a template with the given binding
      # @param template_name [String] Name of the template (without .txt.erb extension)
      # @param binding_context [Binding] Binding context with variables
      # @return [String] Rendered template
      def render(template_name, binding_context)
        template_path = File.join(PROMPTS_DIR, "#{template_name}.txt.erb")
        
        unless File.exist?(template_path)
          raise "Template not found: #{template_path}"
        end

        template_content = File.read(template_path)
        erb = ERB.new(template_content, trim_mode: "-")
        erb.result(binding_context)
      end

      # Render a template with a hash of variables
      # @param template_name [String] Name of the template
      # @param vars [Hash] Variables to make available in the template
      # @return [String] Rendered template
      def render_with_vars(template_name, vars)
        render(template_name, binding_from_hash(vars))
      end

      private

      # Create a binding from a hash of variables
      def binding_from_hash(vars)
        obj = Object.new
        vars.each do |key, value|
          # Validate key is a valid Ruby identifier to prevent injection
          key_str = key.to_s
          unless key_str =~ /\A[a-z_][a-z0-9_]*\z/i
            raise ArgumentError, "Invalid variable name: #{key_str}"
          end
          
          obj.instance_variable_set("@#{key_str}", value)
          obj.define_singleton_method(key_str) { instance_variable_get("@#{key_str}") }
        end
        obj.instance_eval { binding }
      end
    end
  end
end
