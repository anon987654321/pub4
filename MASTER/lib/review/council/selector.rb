# frozen_string_literal: true

module Master
  module Review
    module Council
      # Selects the minimal relevant persona set for a task.
      # Security, Reliability, Maintainer always veto-capable when present.
      class Selector
        ALWAYS_INCLUDED = ["Maintainer"].freeze

        TASK_PERSONAS = {
          mobile_ui: ["User Advocate", "Accessibility", "Web Designer", "Performance", "Google CSS Engineer"],
          ui: ["User Advocate", "Accessibility", "NNGroup UX Researcher", "Web Designer", "Typographer", "Cognitive Psychologist", "Graphic Designer"],
          auth_mutation: ["Security", "Reliability", "Maintainer", "Ethics & Policy"],
          security_audit: %w[Security Reliability Maintainer Skeptic],
          architecture: %w[Architect Maintainer Reliability Skeptic Pragmatist],
          migration: ["Architect", "Maintainer", "Data Steward", "Reliability"],
          performance: ["Performance", "Maintainer", "QA Engineer"],
          data: ["Data Steward", "Maintainer", "Reliability"],
          sonic: [
            "Electronic Music Producer", "Sound Engineer", "Label Executive",
            "Graphic Designer", "Web Designer", "Sound Designer", "Organ Composer",
            "Hip-Hop Producer", "Skeptic"
          ],
          product: ["Product Strategist", "User Advocate", "Pragmatist"],
          docs: ["Maintainer", "Layperson", "QA Engineer"],
          code_review: ["Maintainer", "Skeptic", "QA Engineer", "Architect", "Pragmatist"],
          destructive: %w[Security Reliability Maintainer Architect Skeptic],
        }.freeze

        # A ladder: each level seats everyone the level below it does, plus more.
        # It did not. `high` dropped the Skeptic that `medium` required and
        # `critical` then asked for again, so escalating a change from medium to
        # high risk *removed* a reviewer — the one whose job is to disbelieve the
        # claim. Nothing chose that; medium and high were written at different
        # times. test_council_selector.rb asserts the nesting now.
        RISK_PERSONAS = {
          critical: %w[Security Reliability Maintainer Architect Skeptic],
          high: %w[Security Reliability Maintainer Skeptic],
          medium: %w[Maintainer Skeptic],
          low: ["Maintainer"],
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

        # Union, and the trailing `if` is gone.
        #
        # It read `task_set || risk_set || ALWAYS_INCLUDED if task_set.nil? ||
        # risk_set.nil?`, where the modifier guards the whole expression: with
        # BOTH a task and a risk the condition is false, the method returns nil,
        # and `select` then calls `nil + ALWAYS_INCLUDED`. So
        # `Selector.for(task: :ui, risk: :high)` raised NoMethodError -- the most
        # natural call this class has, and the only one no test made. Every
        # caller in the tree passes a task alone.
        #
        # Union rather than a precedence, because the two axes answer different
        # questions: the task says who understands the change, the risk says who
        # must sign it off. A critical-risk docs edit still wants Security and
        # the Skeptic in the room, and a UI change at low risk still wants the
        # typographer.
        def base_personas(task, risk)
          task_set = task ? TASK_PERSONAS[task.to_sym] : nil
          risk_set = risk ? RISK_PERSONAS[risk.to_sym] : nil
          return ALWAYS_INCLUDED.dup if task_set.nil? && risk_set.nil?
          return task_set.dup if risk_set.nil?
          return risk_set.dup if task_set.nil?

          (task_set + risk_set).uniq
        end

        # `nil unless available` returns nil either way -- nil when there is no
        # list, and nil when there is one, because the expression being guarded
        # is the literal nil. So @available was always nil, the filter in #select
        # never ran, and a caller that passed the personas it actually has
        # configured got back names for personas that do not exist. The
        # parameter has been inert since it was added.
        def normalize_available(available)
          return nil if available.nil?

          Array(available).map(&:to_s)
        end
      end
    end
  end
end
