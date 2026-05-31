# frozen_string_literal: true

module Master
  module Judge
    module Council
      # Selects the minimal relevant persona set for a task.
      # Security, Reliability, Maintainer always veto-capable when present.
      class Selector
        ALWAYS_INCLUDED = ["Maintainer"].freeze

        TASK_PERSONAS = {
          mobile_ui: ["User Advocate", "Accessibility", "Web Designer", "Performance", "Google CSS Engineer"],
          ui: ["User Advocate", "Accessibility", "NNGroup UX Researcher", "Graphic Designer"],
          auth_mutation: ["Security", "Reliability", "Maintainer", "Ethics & Policy"],
          security_audit: ["Security", "Reliability", "Maintainer", "Skeptic"],
          architecture: ["Architect", "Maintainer", "Reliability", "Skeptic"],
          migration: ["Architect", "Maintainer", "Data Steward", "Reliability"],
          performance: ["Performance", "Maintainer", "QA Engineer"],
          data: ["Data Steward", "Maintainer", "Reliability"],
          sonic: ["Hip-Hop Producer", "Electronic Music Producer", "Pragmatist"],
          product: ["Product Strategist", "User Advocate", "Pragmatist"],
          docs: ["Maintainer", "Layperson", "QA Engineer"],
          code_review: ["Maintainer", "Skeptic", "QA Engineer", "Architect"],
          destructive: ["Security", "Reliability", "Maintainer", "Architect", "Skeptic"]
        }.freeze

        RISK_PERSONAS = {
          critical: ["Security", "Reliability", "Maintainer", "Architect", "Skeptic"],
          high: ["Security", "Reliability", "Maintainer"],
          medium: ["Maintainer", "Skeptic"],
          low: ["Maintainer"]
        }.freeze

        def self.for(task: nil, risk: nil, available: nil)
          new(available:).select(task:, risk:)
        end

        def initialize(available: nil)
          @available = normalize_available(available)
        end

        def select(task: nil, risk: nil)
          names = base_personas(task, risk)
          names = (names + ALWAYS_INCLUDED).uniq
          @available ? names.select { |n| @available.include?(n) } : names
        end

        private

        def base_personas(task, risk)
          task_set = task ? TASK_PERSONAS[task.to_sym] : nil
          risk_set = risk ? RISK_PERSONAS[risk.to_sym] : nil
          return task_set || risk_set || ALWAYS_INCLUDED if task_set.nil? || risk_set.nil?
          (task_set + risk_set).uniq
        end

        def normalize_available(available)
          return nil unless available
          Array(available).map(&:to_s).to_set
        end
      end
    end
  end
end
