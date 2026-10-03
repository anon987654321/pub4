# frozen_string_literal: true

module Master
  # Canonical vocabulary for normative guidance. Different disciplines use
  # different names for substantially the same object; MASTER stores and
  # executes that object as a Law.
  module LawVocabulary
    CANONICAL = "law"

    TERMS = {
      "law" => :synonym,
      "laws" => :synonym,
      "rule" => :synonym,
      "rules" => :synonym,
      "principle" => :synonym,
      "principles" => :synonym,
      "convention" => :synonym,
      "conventions" => :synonym,
      "standard" => :synonym,
      "standards" => :synonym,
      "guideline" => :synonym,
      "guidelines" => :synonym,
      "heuristic" => :synonym,
      "heuristics" => :synonym,
      "usability heuristic" => :synonym,
      "usability guideline" => :synonym,
      "design heuristic" => :synonym,
      "design principle" => :synonym,
      "style rule" => :synonym,
      "style guide" => :synonym,
      "engineering principle" => :synonym,
      "engineering rule" => :synonym,
      "best practice" => :synonym,
      "best practices" => :synonym,
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

    NORMALIZE_KEY = lambda do |term|
      term.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/[_\s]+/, " ")
    end.freeze

    NORMALIZED = TERMS.transform_keys { |term| NORMALIZE_KEY.call(term) }.freeze

    module_function

    def normalize(term)
      key = NORMALIZE_KEY.call(term)
      return CANONICAL if NORMALIZED[key] == :synonym

      term.to_s.strip
    end

    def known?(term)
      NORMALIZED.key?(NORMALIZE_KEY.call(term))
    end

    def synonymous?(left, right)
      return false unless known?(left) && known?(right)

      normalize(left) == normalize(right)
    end

    def relation(term)
      NORMALIZED[NORMALIZE_KEY.call(term)]
    end

    def aliases
      TERMS.filter_map { |term, relation| term if relation == :synonym }.freeze
    end

    def prompt
      synonymous = aliases.sort.join(", ")
      "#{CANONICAL} is MASTER's canonical term for normative guidance; "         "synonyms include #{synonymous}. Policy, constraint, invariant, criterion "         "and practice are related concepts and may need their native technical meaning."
    end

  end
end
