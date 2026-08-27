# frozen_string_literal: true

require_relative "baseline_ratchet"

module Pub4
  # What a model promises, measured instead of counted by hand.
  #
  # Both numbers below sat in OPENBSD/data/debt.yml as bare figures — "104
  # associations with no inverse_of", "11 models with no validations" — with the
  # entry itself warning that no committed tool reproduces them and that "an
  # unfalsifiable number is how a register row outlives its subject". A plain
  # grep answers 569 and 48, because it cannot make the exclusions the audit made
  # by hand. This file makes them.
  #
  # uninferrable_inverse — Rails already sets inverse_of for you. ActiveRecord's
  # automatic_inverse_of walks the reflection and finds the other side by name,
  # so the overwhelming majority of associations need nothing. It gives up in
  # specific, documented cases: an association carrying a scope, or :through, or
  # a :foreign_key that breaks the name-based guess. Those are the ones where the
  # inverse is genuinely absent, and where a parent and its loaded child become
  # two different objects in memory — which is how a validation reads a stale
  # value and how strict_loading_by_default raises on a record you already have.
  # :through is excluded: it has no single inverse to declare.
  #
  # no_validations — a model that promises nothing. Not automatically a defect:
  # join tables, reference data and models fully constrained at the database are
  # legitimately validation-free, which is exactly why this is a ratchet and not
  # a bar. It may only fall. Mark a deliberate one with
  # `# model_contract: no-validations-ok — <reason>` and it stops counting.
  #
  # Neither number is a target to drive to zero. They are numbers that cannot
  # grow without someone noticing, which is the property the register row asked
  # for and never had.
  module ModelContractLint
    RAILS_ROOT = File.expand_path("../../..", __dir__)

    MODEL_GLOBS = [
      "{amber,brgen,bsdports,shared}/app/models/**/*.rb",
      "brgen/engines/*/app/models/**/*.rb"
    ].freeze

    ASSOCIATION = /^\s*(has_many|has_one|belongs_to)\s+:(\w+)([^\n]*)$/
    VALIDATION = /^\s*(validates?|validates_\w+|has_secure_password)\b/
    VALIDATION_OPT_OUT = "model_contract: no-validations-ok"

    # Measured 2026-08-25, the first run of this file, and recorded rather than
    # aspired to: a new lint over existing debt starts where the tree is, or it
    # fails on arrival and gets deleted instead of driven down.
    #
    # The register's hand counts were 104 and 11. no_validations lands at 10,
    # which is close enough to trust the exclusions. uninferrable_inverse lands
    # at 54 against 104 because half of what a grep calls a missing inverse_of is
    # an association Rails infers by itself — reporting those would be reporting
    # Rails working. Only falls; never raise to silence a failing run.
    BASELINES = { "uninferrable_inverse" => 54, "no_validations" => 9 }.freeze

    Finding = Struct.new(:kind, :file, :line, :detail)

    extend Pub4::BaselineRatchet

    module_function

    def model_files
      MODEL_GLOBS.flat_map { |glob| Dir.glob(File.join(RAILS_ROOT, glob)) }.uniq.sort
    end

    def scan
      model_files.flat_map { |path| findings_for(path, File.read(path, encoding: "UTF-8").scrub) }
    end

    def findings_for(path, src)
      rel = path.sub("#{RAILS_ROOT}/", "")
      inverse_findings(rel, src) + validation_findings(rel, src)
    end

    # Rails infers the inverse unless the association is one it documents itself
    # as giving up on. Anything it can infer needs no declaration and is not a
    # finding — reporting it would be reporting Rails working.
    def inverse_findings(rel, src)
      src.lines.each_with_index.filter_map do |line, index|
        match = line.match(ASSOCIATION) or next
        options = match[3].to_s
        next if options.include?("inverse_of")
        next if options.include?("through:")          # no single inverse to name
        next if options.include?("polymorphic:")      # many possible inverses
        next unless uninferrable?(line, options)

        Finding.new("uninferrable_inverse", rel, index + 1, "#{match[1]} :#{match[2]}")
      end
    end

    # A scope, a :foreign_key, or an :as makes the name-based guess fail. The
    # scope case is the one that catches people: `has_many :recent, -> { ... }`
    # looks ordinary and is not inferrable.
    def uninferrable?(line, options)
      return true if options.include?("foreign_key:")
      return true if options.include?("as:")

      # A scope is a lambda or proc passed before the options hash.
      line.match?(/,\s*(->|lambda|proc|Proc)/)
    end

    def validation_findings(rel, src)
      return [] if src.include?(VALIDATION_OPT_OUT)
      return [] if src.match?(/self\.abstract_class\s*=\s*true/)
      return [] unless src.match?(/<\s*ApplicationRecord\b/)
      return [] if src.match?(VALIDATION)

      line = src.lines.index { |l| l.match?(/<\s*ApplicationRecord\b/) }.to_i + 1
      [Finding.new("no_validations", rel, line, "promises nothing")]
    end

    def run
      findings = scan
      tally = counts(findings)
      over = tally.select { |kind, count| count > BASELINES.fetch(kind) }

      over.each_key do |kind|
        warn "model_contract_lint: #{kind} #{tally[kind]} exceeds baseline #{BASELINES.fetch(kind)}"
      end
      tally.each { |kind, count| puts "model_contract_lint: #{kind} #{count} (baseline #{BASELINES.fetch(kind)})" }
      findings.select { |f| over.key?(f.kind) }.first(20).each do |f|
        puts "  #{f.kind} #{f.file}:#{f.line} #{f.detail}"
      end
      over.empty?
    end
  end
end

exit(Pub4::ModelContractLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
