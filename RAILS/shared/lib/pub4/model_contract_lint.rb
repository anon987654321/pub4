# frozen_string_literal: true

require_relative "baseline_ratchet"

module Pub4
  # What a model promises, measured instead of counted by hand.
  #
  # Both numbers below sat in TODO.md as bare figures — "104
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
    INVERSE_OPT_OUT = "model_contract: no-inverse-ok"

    # Only falls; never raise to silence a failing run.
    #
    # uninferrable_inverse is 0. It opened at 54 against a hand count of 104 —
    # half of what a grep calls a missing inverse_of is an association Rails
    # infers by itself, and reporting those is reporting Rails working. Reading
    # the whole statement rather than its first line moved 54 to 57: four
    # declared their inverse_of on a continuation line and were false positives,
    # and eight wrapped their foreign_key onto one and were never seen. All 57
    # were then resolved — 55 by naming the inverse, two by the marker above,
    # where the other side genuinely does not exist.
    # no_validations is 0 from 9. Two gained a real validation — PrivacySetting
    # and MessageReceipt each mirror a unique index that was otherwise reached
    # as a 500 — and seven carry the marker with their reason. Tagging is the
    # one worth reading: a tagging is an occurrence, and hashtag_test.rb tags
    # one post twice on purpose, so uniqueness there would be wrong rather than
    # missing. A count driven to zero by re-exempting is worthless; a count
    # driven to zero by writing down why each row is deliberate is the record
    # this file wanted.
    BASELINES = { "uninferrable_inverse" => 0, "no_validations" => 0 }.freeze

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
      lines = src.lines
      lines.each_with_index.filter_map do |line, index|
        match = line.match(ASSOCIATION) or next
        options = wrapped_options(lines, index, match[3].to_s)
        next if options.include?("inverse_of")
        next if opted_out?(lines, index, options)
        next if options.include?("through:")          # no single inverse to name
        next if options.include?("polymorphic:")      # many possible inverses
        next unless uninferrable?(options)

        Finding.new("uninferrable_inverse", rel, index + 1, "#{match[1]} :#{match[2]}")
      end
    end

    # Some associations have no other side to name: brgen's Message belongs_to a
    # sender the User model does not collect. The marker carries the reason on
    # the association or in the comment block above it, so a deliberate one
    # reads as a decision instead of sitting in the count forever.
    def opted_out?(lines, index, options)
      return true if options.include?(INVERSE_OPT_OUT)

      index -= 1
      while index >= 0 && lines[index].strip.start_with?("#")
        return true if lines[index].include?(INVERSE_OPT_OUT)

        index -= 1
      end
      false
    end

    # An association is one statement however many lines it takes, and reading
    # only the first called four declared inverse_of options missing — the
    # option had wrapped onto the continuation line.
    def wrapped_options(lines, index, options)
      while options.rstrip.end_with?(",", "\\")
        index += 1
        following = lines[index] or break

        options += following
      end
      options
    end

    # A scope, a :foreign_key, or an :as makes the name-based guess fail. The
    # scope case is the one that catches people: `has_many :recent, -> { ... }`
    # looks ordinary and is not inferrable.
    def uninferrable?(options)
      return true if options.include?("foreign_key:")
      return true if options.include?("as:")

      # A scope is a lambda or proc passed before the options hash.
      options.match?(/\A,\s*(->|lambda|proc|Proc)/)
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
