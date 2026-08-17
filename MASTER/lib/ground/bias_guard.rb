# frozen_string_literal: true

module Master
  module Ground
    class BiasGuard
      BIAS_PATH = "data/biases.yml".freeze
      SEVERITY_WEIGHT = { critical: 4.0, error: 3.0, warning: 2.0, info: 1.0 }.freeze

      def initialize(root: Master::ROOT)
        @root = root
        @biases = load_biases
      end

      def annotate(proposal)
        hits = detect(proposal)
        return proposal if hits.empty?

        note = hits.map { |name| "#{name}: #{countermeasure(name)}" }.join("; ")
        note += " | compounding: #{cascades(hits).join(', ')}" if cascades(hits).any?
        proposal.to_h.merge(
          reason: "#{proposal.reason} | bias check: #{note}",
          confidence: [proposal.confidence.to_f - 0.1, 0.1].max,
        )
      end

      # The patterns live in data/biases.yml beside the countermeasure they earn.
      # They were fourteen lines of Ruby here, which meant adding a bias took two
      # edits and the yml drifted from what actually fired — the spec-versus-
      # enforcement split this guard exists to notice in other people's work.
      #
      # `clears` is the evidence that acquits: a proposal that measured something
      # is not accused of calling it small.
      def detect(proposal)
        text = "#{proposal.action} #{proposal.reason}".downcase
        @biases.filter_map do |name, body|
          next unless body["detect"] && text.match?(Regexp.new(body["detect"]))
          next if body["clears"] && text.match?(Regexp.new(body["clears"]))

          name
        end
      end

      # Which biases feed each other. The register that asked for these asked for
      # the chains too: anchoring narrows the search, confirmation then only looks
      # for agreement, and availability supplies the first example that fits. Named
      # here so a proposal carrying two links of one chain says so, rather than
      # reporting two unrelated-looking notes.
      def cascades(hits)
        hits.filter_map do |name|
          linked = Array(@biases.dig(name, "compounds_with")) & hits
          "#{name}->#{linked.join('+')}" unless linked.empty?
        end
      end

      def priority_score(severity:, frequency:, age_days:)
        sev = SEVERITY_WEIGHT.fetch(severity.to_sym, 1.0)
        age = [[age_days.to_f, 0.0].max, 365.0].min
        sev * frequency.to_f * (1.0 + (age / 30.0))
      end

      private

      def countermeasure(name)
        @biases.dig(name, "countermeasure").to_s
      end

      def load_biases
        path = File.join(@root, BIAS_PATH)
        File.exist?(path) ? Master.load_yaml(path) : {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "BiasGuard.load_biases")
        {}
      end
    end
  end
end
