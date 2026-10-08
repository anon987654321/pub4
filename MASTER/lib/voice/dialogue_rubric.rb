# frozen_string_literal: true

module Master
  module Voice
    # The conversational constitution is data, not a second personality file.
    # Examples are fixtures; the runtime renders the rules that are meant to
    # reach the model. Bench code reads the same file, so law and proof cannot
    # quietly diverge.
    module DialogueRubric
      PATH = File.join(Master::DATA, "dialogue_rubric.yml").freeze

      module_function

      def data(root: Master::ROOT)
        path = File.join(root, "data", "dialogue_rubric.yml")
        return {} unless File.file?(path)

        payload = Master.load_yaml(path) || {}
        validate!(payload)
        payload
      end

      def dimensions(root: Master::ROOT)
        data(root:).fetch("dimensions", {})
      end

      def fixtures(root: Master::ROOT)
        Array(data(root:)["sycophancy_fixtures"])
      end

      def prompt_block(root: Master::ROOT)
        items = dimensions(root:)
        return if items.empty?

        lines = items.map { |name, item| "- #{name}: #{item.fetch("rule")}" }
        <<~XML.strip
          <master_dialogue_rubric>
          Conversation law:
          #{lines.join("
")}
          Lead with substance. Calibrate certainty to evidence. Disagree when a claim is wrong or a plan is weak, and give the reason. Repair ambiguity plainly. Do not use canned assistant openers.
          </master_dialogue_rubric>
        XML
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "dialogue_rubric.prompt_block", severity: :cosmetic)
        nil
      end

      def evaluate(response, root: Master::ROOT)
        text = response.to_s.strip
        return [] if text.empty?

        failures = []
        Array(data(root:).dig("bench", "forbidden_openers")).each do |phrase|
          failures << "no_ai_isms: #{phrase}" if text.match?(/A#{Regexp.escape(phrase)}/i)
        end
        failures
      end

      def valid?(root: Master::ROOT)
        validate!(data(root:))
      rescue ArgumentError
        false
      end

      def validate!(payload)
        dimensions = payload["dimensions"]
        fixtures = payload["sycophancy_fixtures"]
        raise ArgumentError, "dialogue rubric dimensions missing" unless dimensions.is_a?(Hash) && dimensions.any?
        raise ArgumentError, "dialogue rubric fixtures missing" unless fixtures.is_a?(Array) && fixtures.any?

        dimensions.each do |name, item|
          raise ArgumentError, "dialogue rubric #{name} missing rule" if item["rule"].to_s.strip.empty?
          raise ArgumentError, "dialogue rubric #{name} missing bad/good fixture" if item["bad"].to_s.empty? || item["good"].to_s.empty?
        end
        fixtures.each do |fixture|
          raise ArgumentError, "dialogue fixture missing id" if fixture["id"].to_s.empty?
          raise ArgumentError, "dialogue fixture missing user/bad/good" if [fixture["user"], fixture["bad"], fixture["good"]].any? { |value| value.to_s.empty? }
        end
        true
      end
      private_class_method :validate!
    end
  end
end
