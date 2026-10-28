# frozen_string_literal: true

module Master
  # Provider-key and execution metadata must agree before runtime configuration
  # touches RubyLLM. Keep this separate from the model catalogue schema.
  module ProviderCatalogueGuard
    module_function

    PROVIDER_FIELDS = %w[
      env command strengths default_model model_pattern ruby_llm_key min_key_length
    ].freeze
    def validate(data)
      errors = []
      errors << "providers.yml schema must be 1" unless data["schema"] == 1
      providers = data.reject { |name, _row| name.to_s == "schema" }
      errors << "providers.yml must contain provider mappings" if providers.empty?

      providers.each do |name, row|
        unless name.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
          errors << "providers.yml has invalid provider name #{name.inspect}"
        end
        unless row.is_a?(Hash)
          errors << "provider #{name} must be a mapping"
          next
        end

        unknown = row.keys.map(&:to_s) - PROVIDER_FIELDS
        errors << "provider #{name} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?

        env = row["env"]
        unless env.is_a?(Array) && env.uniq == env &&
               env.all? { |value| value.is_a?(String) && value.match?(/\A[A-Z][A-Z0-9_]*\z/) }
          errors << "provider #{name}.env must be a unique list of environment-variable names"
        end

        strengths = row["strengths"]
        unless strengths.is_a?(Array) && !strengths.empty? &&
               strengths.all? { |value| value.is_a?(String) && value.match?(/\A[a-z][a-z0-9_]*\z/) }
          errors << "provider #{name}.strengths must be a non-empty list of capability names"
        end

        unless row["default_model"].is_a?(String) && !row["default_model"].strip.empty?
          errors << "provider #{name}.default_model must be non-empty text"
        end

        if row.key?("command") && !(row["command"].is_a?(String) && !row["command"].strip.empty?)
          errors << "provider #{name}.command must be non-empty text"
        end

        if row.key?("model_pattern")
          pattern = row["model_pattern"]
          if !pattern.is_a?(String) || pattern.empty?
            errors << "provider #{name}.model_pattern must be non-empty regex text"
          else
            begin
              Regexp.new(pattern)
            rescue RegexpError => error
              errors << "provider #{name}.model_pattern is invalid: #{error.message}"
            end
          end
        end

        key = row["ruby_llm_key"]
        minimum = row["min_key_length"]
        if key.nil? != minimum.nil?
          errors << "provider #{name} must declare ruby_llm_key and min_key_length together"
        end
        unless key.nil?
          errors << "provider #{name}.ruby_llm_key must be a snake_case key name" unless
            key.is_a?(String) && key.match?(/\A[a-z][a-z0-9_]*\z/)
          errors << "provider #{name} needs at least one key environment variable" unless
            env.is_a?(Array) && !env.empty?
          errors << "provider #{name}.min_key_length must be a positive integer" unless
            minimum.is_a?(Integer) && minimum.positive?
        end
      end

      raise ArgumentError, errors.uniq.join("; ") unless errors.empty?
      true
    end

  end
end
