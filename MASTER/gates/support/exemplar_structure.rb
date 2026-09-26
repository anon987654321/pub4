# frozen_string_literal: true

require "yaml"

module Deploy
  # Score HTML against structural exemplars (P3 design skill).
  # Distance-to-good-grammar, not pixel clone of competitor screenshots.
  class ExemplarStructure
    DATA = File.join(File.expand_path("..", __dir__), "data", "exemplars.yml")

    Result = Struct.new(:id, :score, :max, :target, :missing_required, :notes, keyword_init: true) do
      def pass?
        missing_required.empty? && score >= target
      end

      def ratio
        max.positive? ? (score.to_f / max).round(3) : 0.0
      end
    end

    def self.load(path = DATA)
      YAML.safe_load_file(path)
    end

    def initialize(data: nil)
      @data = data || self.class.load
      @exemplars = @data.fetch("exemplars")
    end

    def score(html, exemplar_id)
      spec = @exemplars[exemplar_id.to_s]
      raise ArgumentError, "unknown exemplar #{exemplar_id}" unless spec

      body = normalize(html)
      max = 0
      earned = 0
      missing = []
      notes = []

      Array(spec["parts"]).each do |part|
        points = part["points"].to_i
        max += points
        ok =
          if part["order"]
            order_ok?(body, part["order"])
          elsif part["forbid"]
            !body.match?(compile(part["forbid"]))
          elsif part["pattern"]
            body.match?(compile(part["pattern"]))
          else
            false
          end

        if ok
          earned += points
        else
          notes << "miss:#{part['id']}"
          missing << part["id"] if part["required"]
        end
      end

      Result.new(
        id: exemplar_id.to_s,
        score: earned,
        max: max,
        target: spec["target_score"].to_i,
        missing_required: missing,
        notes: notes
      )
    end

    def score_all(html_by_id)
      html_by_id.map { |id, html| score(html, id) }
    end

    private

    def normalize(html)
      body = html.to_s.dup.force_encoding(Encoding::UTF_8)
      body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless body.valid_encoding?
      body
    end

    def compile(pattern)
      return pattern if pattern.is_a?(Regexp)

      Regexp.new(pattern.to_s, Regexp::IGNORECASE)
    end

    # order: array of alternate-pattern strings; each step must appear after previous
    def order_ok?(body, steps)
      last = -1
      Array(steps).all? do |step|
        pat = compile(step)
        idx = body =~ pat
        next false unless idx
        next false if idx < last

        last = idx
        true
      end
    end
  end
end
