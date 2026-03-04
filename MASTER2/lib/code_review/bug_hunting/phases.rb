# frozen_string_literal: true

module CodeReview
  module BugHunting
    class Phases
      DEFAULT_INCLUDES = %i[author files comments].freeze

      def initialize(review_scope: Review.all)
        @review_scope = review_scope
      end

      def analyze(review_id)
        review = load_review(review_id)
        return [] unless review

        findings = []
        findings.concat(analyze_security(review))
        findings.concat(analyze_performance(review))
        findings
      end

      private

      attr_reader :review_scope

      def load_review(id)
        review_scope.includes(*DEFAULT_INCLUDES).find_by(id: id)
      end

      def analyze_security(review)
        findings = []
        add_finding(findings, :authorization, "Missing authorization checks") if review.respond_to?(:missing_auth?) && review.missing_auth?
        add_finding(findings, :input_validation, "Insufficient input validation") if review.respond_to?(:weak_validation?) && review.weak_validation?
        findings
      end

      def analyze_performance(review)
        findings = []
        add_finding(findings, :data_access, "Potential N+1 queries") if review.respond_to?(:n_plus_one_risk?) && review.n_plus_one_risk?
        findings
      end

      def add_finding(list, category, desc)
        list << { category: category.to_s, desc: desc }
      end
    end
  end
end