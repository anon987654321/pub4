# frozen_string_literal: true

require "yaml"
require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  # Structural HTML contracts for first-screen surfaces.
  # Works on rendered HTML or static fixtures (no browser).
  # Markers are regex patterns; order is document-order of first match.
  class DomSurfaceSchema
    ROOT = File.expand_path("../../..", __dir__)
    SCHEMA_PATH = File.join(File.expand_path("..", __dir__), "data", "surface_schemas.yml")

    Finding = Struct.new(:schema_id, :severity, :principle, :message, keyword_init: true)

    def self.load_all(path = SCHEMA_PATH)
      data = YAML.safe_load_file(path)
      data.fetch("schemas")
    end

    def self.check(html, schema_id, schemas: nil)
      new(schemas: schemas).check(html, schema_id)
    end

    def initialize(schemas: nil)
      @schemas = schemas || self.class.load_all
    end

    # Returns Array<Finding>
    def check(html, schema_id)
      schema = @schemas[schema_id.to_s] || @schemas[schema_id.to_sym]
      raise ArgumentError, "unknown surface schema: #{schema_id}" unless schema

      body = html.to_s
      body = body.dup.force_encoding(Encoding::UTF_8)
      body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless body.valid_encoding?
      findings = []
      default_sev = (schema["severity_default"] || "hard").to_sym
      label = schema["label"] || schema_id

      markers = schema["markers"] || {}
      positions = {}

      markers.each do |mid, spec|
        pat = compile(spec["pattern"])
        sev = (spec["severity"] || default_sev).to_sym
        principle = spec["principle"] || schema["principle"]
        idx = body =~ pat
        positions[mid.to_s] = idx
        if idx.nil?
          findings << Finding.new(
            schema_id: schema_id.to_s,
            severity: sev,
            principle: principle,
            message: "surface_schema:#{schema_id} missing marker #{mid} (#{label}) principle=#{principle}"
          )
        end
      end

      # Presence cannot say "exactly one", which is how drop_h1 and duplicate_h1 both survived.
      (schema["counts"] || {}).each do |cid, spec|
        found = body.scan(compile(spec["pattern"])).size
        sev = (spec["severity"] || default_sev).to_sym
        principle = spec["principle"] || schema["principle"]
        bound = count_violation(found, spec)
        next unless bound

        findings << Finding.new(
          schema_id: schema_id.to_s,
          severity: sev,
          principle: principle,
          message: "surface_schema:#{schema_id} #{cid} #{bound} (#{label}) principle=#{principle}"
        )
      end

      Array(schema["order"]).each do |pair|
        a, b = pair.map(&:to_s)
        ia = positions[a]
        ib = positions[b]
        next if ia.nil? || ib.nil?

        next if ia < ib

        findings << Finding.new(
          schema_id: schema_id.to_s,
          severity: default_sev,
          principle: schema["principle"],
          message: "surface_schema:#{schema_id} order: #{a} must precede #{b} (#{label})"
        )
      end

      Array(schema["forbidden"]).each do |spec|
        pat = compile(spec["pattern"])
        next unless body.match?(pat)

        sev = (spec["severity"] || default_sev).to_sym
        principle = spec["principle"] || schema["principle"]
        note = spec["note"]
        msg = "surface_schema:#{schema_id} forbidden #{pat.inspect}"
        msg += " — #{note}" if note
        msg += " principle=#{principle}"
        findings << Finding.new(
          schema_id: schema_id.to_s,
          severity: sev,
          principle: principle,
          message: msg
        )
      end

      findings
    end

    def apply_to_result!(result, html, schema_id)
      check(html, schema_id).each do |finding|
        result.fail(finding.message, severity: finding.severity)
      end
      result
    end

    private

    def count_violation(found, spec)
      return "found #{found}, needs at least #{spec["min"]}" if spec["min"] && found < spec["min"]
      return "found #{found}, allows at most #{spec["max"]}" if spec["max"] && found > spec["max"]

      nil
    end

    def compile(pattern)
      return pattern if pattern.is_a?(Regexp)

      Regexp.new(pattern.to_s, Regexp::IGNORECASE)
    end
  end
end
