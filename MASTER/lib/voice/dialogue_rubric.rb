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

        bench = data(root:).fetch("bench", {})
        failures = []
        Array(bench["forbidden_openers"]).each do |phrase|
          failures << "no_ai_isms: #{phrase}" if text.match?(/\A#{Regexp.escape(phrase)}/i)
        end
        asked = question_count(text)
        limit = bench.fetch("questions_per_turn_max", 1).to_i
        failures << "one_question: #{asked} questions (max #{limit})" if asked > limit
        failures
      end

      # Ignore code spans/fences and count question punctuation closing prose questions.
      def question_count(text)
        prose = text.gsub(/\x60\x60\x60.*?\x60\x60\x60/m, " ")
        prose = prose.gsub(/\x60\x60\x60.*\z/m, " ")
        prose = prose.gsub(/\x60+[^\x60\n]*\x60+/, " ")
        prose.scan(/\?(?=(?:["\x27\)\]\u2019\u201D]*\s|\z))/).size
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

        bench = payload["bench"]
        raise ArgumentError, "dialogue rubric bench missing" unless bench.is_a?(Hash)
        required_dimensions = Array(bench["required_dimensions"]).map(&:to_s)
        raise ArgumentError, "dialogue rubric required dimensions drift" unless required_dimensions == dimensions.keys.map(&:to_s)
        raise ArgumentError, "dialogue rubric fixture count drift" unless bench["sycophancy_fixture_count"] == fixtures.length
        question_limit = bench["questions_per_turn_max"]
        raise ArgumentError, "dialogue rubric question limit missing" unless question_limit.is_a?(Integer) && question_limit >= 0

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
