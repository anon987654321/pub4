# frozen_string_literal: true

module MASTER
  module Enforcement
    module Scopes
      REQUIRED_FRAMEWORK_KEYS = %w[name version].freeze

      def check_lines(subject, violations = [])
        each_scope(subject, :lines) { |value, path| validate_lines(value, path, violations) }
        violations
      end

      def check_units(subject, violations = [])
        each_scope(subject, :units) { |value, path| validate_units(value, path, violations) }
        violations
      end

      def check_framework(subject, violations = [])
        each_scope(subject, :framework) { |value, path| validate_framework(value, path, violations) }
        violations
      end

      private

      def each_scope(subject, key)
        scopes = extract_hash(subject)
        return if scopes.empty?

        value = scopes[key.to_sym] || scopes[key.to_s]
        yield(value, key.to_s)
      end

      def extract_hash(subject)
        return subject if subject.is_a?(Hash)

        if subject.respond_to?(:to_h)
          subject.to_h
        else
          {}
        end
      rescue StandardError
        {}
      end

      def validate_lines(value, path, violations)
        return add_violation(violations, "#{path} must be an Array") unless value.is_a?(Array)

        value.each_with_index do |line, idx|
          validate_string_or_hash(line, "#{path}[#{idx}]", violations)
        end
      end

      def validate_units(value, path, violations)
        return add_violation(violations, "#{path} must be an Array") unless value.is_a?(Array)

        value.each_with_index do |unit, idx|
          validate_string_or_hash(unit, "#{path}[#{idx}]", violations)
        end
      end

      def validate_framework(value, path, violations)
        return add_violation(violations, "#{path} must be a Hash") unless value.is_a?(Hash)

        REQUIRED_FRAMEWORK_KEYS.each do |k|
          add_violation(violations, "#{path}.#{k} is required") unless present_key?(value, k)
        end
      end

      def validate_string_or_hash(value, path, violations)
        return if value.is_a?(String)
        return validate_scope_hash(value, path, violations) if value.is_a?(Hash)

        add_violation(violations, "#{path} must be a String or a Hash")
      end

      def validate_scope_hash(value, path, violations)
        unless present_key?(value, "name") || present_key?(value, :name)
          add_violation(violations, "#{path}.name is required")
        end

        if value.key?("metadata") || value.key?(:metadata)
          metadata = value["metadata"] || value[:metadata]
          add_violation(violations, "#{path}.metadata must be a Hash") unless metadata.is_a?(Hash)
        end
      end

      def present_key?(hash, key)
        return false unless hash.is_a?(Hash)

        val = hash[key]
        return false if val.nil?
        return false if val.respond_to?(:empty?) && val.empty?

        true
      end

      def add_violation(violations, message)
        if violations.respond_to?(:<<)
          violations << message
        elsif violations.respond_to?(:add)
          violations.add(message)
        end
      end
    end
  end
end
