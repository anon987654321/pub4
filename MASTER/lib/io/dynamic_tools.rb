# frozen_string_literal: true

require "uri"
require "yaml"

module Master
  module Io
    # Runtime HTTP tool registry (OpenCrabs tools.toml parity) — data-driven endpoints
    # without redeploying Ruby adapters.
    module DynamicTools
      PATHS = [
        File.join(Master::ROOT, "data", "tools.dynamic.yml"),
        File.expand_path("~/.master/tools.dynamic.yml"),
      ].freeze

      module_function

      FIELDS = %w[name enabled method url elevated description body_template content_type].freeze
      METHODS = %w[GET POST PUT PATCH].freeze
      NAME_PATTERN = /\A[a-z][a-z0-9_-]*\z/

      def paths = PATHS

      def load_definitions
        rows = paths.flat_map { |path| load_path(path) }
        duplicates = rows.group_by { |row| row.fetch("name") }.select { |_name, entries| entries.size > 1 }.keys
        raise ArgumentError, "dynamic tool catalogue has duplicate name(s): #{duplicates.sort.join(', ')}" unless duplicates.empty?

        rows.select { |row| row.fetch("enabled", true) }
      end

      def load_path(path)
        return [] unless File.file?(path)

        source = File.read(path, encoding: "UTF-8")
        rows = Master.load_yaml(path)
        if rows.nil?
          empty_source = source.lines.all? { |line| line.strip.empty? || line.lstrip.start_with?("#") }
          return [] if empty_source # comments-only file is an intentionally empty catalogue
        end
        unless rows.is_a?(Array)
          raise ArgumentError, "dynamic tool catalogue #{path} must be a YAML list"
        end

        errors = []
        normalized = rows.each_with_index.filter_map do |row, index|
          label = "#{path}[#{index}]"
          unless row.is_a?(Hash)
            errors << "#{label} must be a mapping"
            next
          end

          unknown = row.keys.map(&:to_s) - FIELDS
          errors << "#{label} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
          name = row["name"]
          unless name.is_a?(String) && name.match?(NAME_PATTERN)
            errors << "#{label}.name must match #{NAME_PATTERN.inspect}"
            next
          end

          enabled = row.fetch("enabled", true)
          elevated = row.fetch("elevated", true)
          errors << "#{label}.enabled must be boolean" unless [true, false].include?(enabled)
          errors << "#{label}.elevated must be boolean" unless [true, false].include?(elevated)

          method = row.fetch("method", "GET")
          unless method.is_a?(String) && METHODS.include?(method.upcase)
            errors << "#{label}.method must be one of #{METHODS.join(', ')}"
          end

          url = row["url"]
          if !url.is_a?(String) || url.strip.empty?
            errors << "#{label}.url must be non-empty HTTP(S) template text"
          else
            begin
              sample = url.gsub(/\{[A-Za-z][A-Za-z0-9_]*\}/, "slot")
              raise URI::InvalidURIError, "malformed interpolation braces" if sample.include?("{") || sample.include?("}")

              uri = URI.parse(sample)
              unless %w[http https].include?(uri.scheme) && !uri.host.to_s.empty? && uri.userinfo.nil? && uri.fragment.nil?
                errors << "#{label}.url must be HTTP(S), have a host, and omit credentials/fragments"
              end
            rescue URI::InvalidURIError => error
              errors << "#{label}.url is invalid: #{error.message}"
            end
          end

          description = row["description"]
          errors << "#{label}.description must be non-empty text" unless description.is_a?(String) && !description.strip.empty?
          if row.key?("body_template") && !(row["body_template"].is_a?(String) && !row["body_template"].empty?)
            errors << "#{label}.body_template must be non-empty text"
          end
          if row.key?("content_type") && !(row["content_type"].is_a?(String) && !row["content_type"].strip.empty?)
            errors << "#{label}.content_type must be non-empty text"
          end

          row.merge("method" => method.is_a?(String) ? method.upcase : method)
        end

        raise ArgumentError, errors.uniq.join("; ") unless errors.empty?
        normalized
      rescue Psych::Exception => error
        raise ArgumentError, "dynamic tool catalogue #{path} has invalid YAML: #{error.message}"
      end

      # Per row, at call time. Every row reaches a model through the one
      # DynamicHttp tool, whose single registry entry cannot carry a different
      # exposure per row. An HTTP endpoint reaches the open world, so a row that
      # does not declare itself unelevated waits for elevation.
      def elevated?(row) = row["elevated"] != false

      def lookup(name)
        load_definitions.find { |row| row["name"].to_s == name.to_s }
      end
    end
  end
end
