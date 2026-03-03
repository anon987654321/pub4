# frozen_string_literal: true

require "yaml"

module Analysis
  OPENBSD_SCHEMA_FILE = "openbsd_config_schema.yml"
  DEFAULT_MAX_ERRORS = 50

  class OpenbsdConfigValidator
    def initialize(max_errors: DEFAULT_MAX_ERRORS)
      @max_errors = max_errors
    end

    def validate(config)
      return errors(["config must be a Hash"]) unless config.is_a?(Hash)

      schema = load_schema
      errs = []
      errs.concat(validate_required(schema, config))
      errs.concat(validate_keys(schema, config))
      errs.concat(validate_values(schema, config))
      limit(errs)
    end

    private

    def load_schema
      path = Paths.data_file(OPENBSD_SCHEMA_FILE)
      contents = read_file(path)
      YAML.safe_load(contents, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    rescue Psych::SyntaxError
      {}
    end

    def read_file(path)
      File.read(path)
    rescue Errno::ENOENT, Errno::EACCES
      "{}"
    end

    def validate_required(schema, config)
      required = Array(schema["required"])
      missing = required.reject { |k| config.key?(k) }
      missing.map { |k| "missing required key: #{k}" }
    end

    def validate_keys(schema, config)
      allowed = schema["allowed_keys"]
      return [] unless allowed.is_a?(Array) && !allowed.empty?

      unknown = config.keys.map(&:to_s) - allowed.map(&:to_s)
      unknown.map { |k| "unknown key: #{k}" }
    end

    def validate_values(schema, config)
      rules = schema["rules"]
      return [] unless rules.is_a?(Hash) && !rules.empty?

      rules.each_with_object([]) do |(key, rule), errs|
        next unless config.key?(key)

        errs.concat(validate_value_rule(key, config[key], rule))
        break if errs.size >= @max_errors
      end
    end

    def validate_value_rule(key, value, rule)
      return [] unless rule.is_a?(Hash)

      errs = []
      errs.concat(validate_type(key, value, rule["type"]))
      errs.concat(validate_enum(key, value, rule["enum"]))
      errs.concat(validate_range(key, value, rule["min"], rule["max"]))
      errs
    end

    def validate_type(key, value, type_name)
      return [] if type_name.nil?

      ok = case type_name
           when "String" then value.is_a?(String)
           when "Integer" then value.is_a?(Integer)
           when "Boolean" then value == true || value == false
           when "Array" then value.is_a?(Array)
           when "Hash" then value.is_a?(Hash)
           else
             true
           end

      ok ? [] : ["#{key} has invalid type (expected #{type_name})"]
    end

    def validate_enum(key, value, allowed)
      return [] unless allowed.is_a?(Array) && !allowed.empty?
      allowed.include?(value) ? [] : ["#{key} must be one of #{allowed.inspect}"]
    end

    def validate_range(key, value, min, max)
      return [] unless value.is_a?(Numeric)
      return [] if min.nil? && max.nil?

      too_low = !min.nil? && value < min
      too_high = !max.nil? && value > max
      return [] unless too_low || too_high

      ["#{key} must be between #{min.inspect} and #{max.inspect}"]
    end

    def limit(errs)
      errs.take(@max_errors)
    end

    def errors(list)
      limit(Array(list))
    end
  end
end