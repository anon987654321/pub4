# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "set"

module MASTER
  class Error < StandardError; end
  class ConstitutionViolation < Error; end
  class InvariantViolation < Error; end
  class SecurityViolation < Error; end

  class EventLog
    def emit(event:, payload:)
      puts JSON.generate(
        ts: Time.now.utc.iso8601,
        event: event,
        payload: payload
      )
    end
  end

  class Change
    REQUIRED = %i[
      id
      author
      patch
      rationale
      rollback
      invariants
      risks
      rejected_alternatives
      confidence
    ].freeze

    attr_reader(*REQUIRED)

    def initialize(attrs)
      missing = REQUIRED.reject { |k| attrs.key?(k) }

      raise ConstitutionViolation, missing.join(",") unless missing.empty?

      REQUIRED.each do |field|
        instance_variable_set("@#{field}", attrs[field])
      end
    end

    def checksum
      Digest::SHA256.hexdigest(patch)
    end
  end

  class Constitution
    FORBIDDEN = [
      /eval\(/,
      /method_missing/,
      /class_eval/,
      /instance_eval/
    ].freeze

    def validate!(change)
      FORBIDDEN.each do |pattern|
        next unless change.patch.match?(pattern)

        raise ConstitutionViolation,
              "forbidden pattern: #{pattern.inspect}"
      end

      unless change.rationale.downcase.include?("rollback")
        raise ConstitutionViolation,
              "rollback rationale required"
      end

      unless change.confidence.between?(0.0, 1.0)
        raise ConstitutionViolation,
              "confidence out of bounds"
      end
    end
  end

  class Reviewer
    QUESTIONS = [
      "Can this become smaller?",
      "Can this become explicit?",
      "Can this be deleted?",
      "Can exhausted maintainers debug this?"
    ].freeze

    def challenge!(change)
      raise ConstitutionViolation, "missing invariants" if change.invariants.empty?
      raise ConstitutionViolation, "missing risks" if change.risks.empty?
      raise ConstitutionViolation, "missing alternatives" if change.rejected_alternatives.empty?

      QUESTIONS
    end
  end

  class InvariantRegistry
    def initialize
      @rules = Set.new
    end

    def register(rule)
      @rules << rule
    end

    def verify!(change)
      missing = @rules.reject do |rule|
        change.invariants.any? { |i| i.include?(rule) }
      end

      return if missing.empty?

      raise InvariantViolation,
            missing.to_a.join(",")
    end
  end

  class Security
    DANGEROUS = {
      "curl | sh" => "remote execution pipeline",
      "rm -rf" => "destructive deletion"
    }.freeze

    def audit!(change)
      violations = []

      DANGEROUS.each do |needle, reason|
        violations << reason if change.patch.include?(needle)
      end

      return if violations.empty?

      raise SecurityViolation, violations.join(",")
    end
  end

  class Runtime
    attr_reader :constitution,
                :reviewer,
                :invariants,
                :security,
                :log

    def initialize
      @constitution = Constitution.new
      @reviewer = Reviewer.new
      @invariants = InvariantRegistry.new
      @security = Security.new
      @log = EventLog.new

      bootstrap!
    end

    def evaluate(change)
      log.emit(
        event: "change.received",
        payload: {
          id: change.id,
          checksum: change.checksum
        }
      )

      constitution.validate!(change)
      reviewer.challenge!(change)
      invariants.verify!(change)
      security.audit!(change)

      log.emit(
        event: "change.accepted",
        payload: {
          id: change.id
        }
      )

      true
    rescue Error => e
      log.emit(
        event: "change.rejected",
        payload: {
          id: change.id,
          error: e.class.name,
          message: e.message
        }
      )

      false
    end

    private

    def bootstrap!
      invariants.register("rollback")
      invariants.register("locality")
      invariants.register("auditability")
      invariants.register("explicit")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  runtime = MASTER::Runtime.new

  change = MASTER::Change.new(
    id: "change-001",
    author: "opus-4.7",
    patch: <<~PATCH,
      diff --git a/runtime.rb b/runtime.rb
      + puts 'explicit behavior'
    PATCH
    rationale: <<~TEXT,
      necessity: remove hidden behavior
      tradeoff: more verbosity for auditability
      rollback: git revert <sha>
      risk: minimal operational change
    TEXT
    rollback: "git revert <sha>",
    invariants: [
      "rollback preserved",
      "locality preserved",
      "auditability preserved",
      "explicit behavior"
    ],
    risks: [
      "minor formatting mismatch"
    ],
    rejected_alternatives: [
      "metaprogramming"
    ],
    confidence: 0.82
  )

  runtime.evaluate(change)
end
