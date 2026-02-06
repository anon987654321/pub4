# frozen_string_literal: true

require 'json'

module MASTER
  module Core
    # Validator for schema-based data validation (Data-Oriented Design #9)
    # Validates data structures against JSON schemas
    class Validator
      SCHEMA_DIR = File.join(MASTER::ROOT, 'schemas')

      class << self
        # Load and cache schemas
        def schemas
          @schemas ||= {}
        end

        # Load a schema by name
        def load_schema(name)
          schemas[name] ||= begin
            path = File.join(SCHEMA_DIR, "#{name}.schema.json")
            return nil unless File.exist?(path)
            JSON.parse(File.read(path))
          end
        end

        # Validate data against a schema
        def validate(data, schema_name)
          schema = load_schema(schema_name)
          return Result.err("Schema not found: #{schema_name}") unless schema

          errors = validate_against_schema(data, schema)
          errors.empty? ? Result.ok(data) : Result.err(errors)
        end

        # Validate message structure
        def validate_message(data)
          validate(data, 'message')
        end

        # Validate persona structure
        def validate_persona(data)
          validate(data, 'persona')
        end

        # Validate principle structure
        def validate_principle(data)
          validate(data, 'principle')
        end

        # Validate debate structure
        def validate_debate(data)
          validate(data, 'debate')
        end

        # Validate embedding structure
        def validate_embedding(data)
          validate(data, 'embedding')
        end

        # Clear schema cache
        def clear_cache
          @schemas = {}
        end

        private

        # Simple JSON schema validator (basic implementation)
        # For production use, consider json-schema gem
        def validate_against_schema(data, schema)
          errors = []

          # Check required fields
          if schema['required']
            schema['required'].each do |field|
              unless data.key?(field) || data.key?(field.to_sym)
                errors << "Missing required field: #{field}"
              end
            end
          end

          # Check types for present fields
          if schema['properties']
            schema['properties'].each do |field, field_schema|
              value = data[field] || data[field.to_sym]
              next unless value

              type_error = validate_type(value, field_schema, field)
              errors << type_error if type_error
            end
          end

          errors
        end

        def validate_type(value, field_schema, field_name)
          expected_type = field_schema['type']
          return nil unless expected_type

          actual_type = case value
                       when String then 'string'
                       when Integer then 'integer'
                       when Float, Numeric then 'number'
                       when TrueClass, FalseClass then 'boolean'
                       when Array then 'array'
                       when Hash then 'object'
                       else 'unknown'
                       end

          # Allow integer where number is expected
          if expected_type == 'number' && actual_type == 'integer'
            return nil
          end

          # Check enum values
          if field_schema['enum'] && !field_schema['enum'].include?(value)
            return "Field '#{field_name}' must be one of: #{field_schema['enum'].join(', ')}"
          end

          # Check minimum/maximum for numbers
          if expected_type == 'number' || expected_type == 'integer'
            if field_schema['minimum'] && value < field_schema['minimum']
              return "Field '#{field_name}' must be >= #{field_schema['minimum']}"
            end
            if field_schema['maximum'] && value > field_schema['maximum']
              return "Field '#{field_name}' must be <= #{field_schema['maximum']}"
            end
          end

          if expected_type != actual_type && !(expected_type == 'number' && actual_type == 'integer')
            return "Field '#{field_name}' expected #{expected_type}, got #{actual_type}"
          end

          nil
        end
      end
    end
  end
end
