# frozen_string_literal: true

module Master
  # Canonical vocabulary for normative guidance. Different disciplines use
  # different names for substantially the same object; MASTER stores and
  # executes that object as a Law.
  module LawVocabulary
    CANONICAL = "law"

    TERMS = {
      "law" => :synonym,
      "rule" => :synonym,
      "principle" => :synonym,
      "convention" => :synonym,
      "standard" => :synonym,
      "guideline" => :synonym,
      "heuristic" => :synonym,
      "usability heuristic" => :synonym,
      "design heuristic" => :synonym,
      "design principle" => :synonym,
      "style rule" => :synonym,
      "style guide" => :synonym,
      "engineering principle" => :synonym,
      "engineering rule" => :synonym,
      "precept" => :synonym,
      "tenet" => :synonym,
      "canon" => :synonym,
      "norm" => :synonym,
      "doctrine" => :synonym,
      "policy" => :related,
      "constraint" => :related,
      "invariant" => :related,
      "criterion" => :related,
      "practice" => :related
    }.freeze

    NORMALIZED = TERMS.transform_keys { |term| normalize_key(term) }.freeze

    module_function

    def normalize(term)
      key = normalize_key(term)
      return CANONICAL if NORMALIZED[key] == :synonym

      term.to_s.strip
    end

    def known?(term)
      NORMALIZED.key?(normalize_key(term))
    end

    def synonymous?(left, right)
      return false unless known?(left) && known?(right)

      normalize(left) == normalize(right)
    end

    def relation(term)
      NORMALIZED[normalize_key(term)]
    end

    def aliases
      TERMS.filter_map { |term, relation| term if relation == :synonym }.freeze
    end

    def prompt
      synonymous = aliases.sort.join(", ")
      "#{CANONICAL} is MASTER's canonical term for normative guidance; "         "synonyms include #{synonymous}. Policy, constraint, invariant, criterion "         "and practice are related concepts and may need their native technical meaning."
    end

    def normalize_key(term)
      term.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/[\\_]+/, " ").gsub(/\\s+/, " ")
    end

    private_class_method :normalize_key
  end
end
