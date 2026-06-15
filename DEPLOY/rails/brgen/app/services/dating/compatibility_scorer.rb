# frozen_string_literal: true
# AN610: LLM compatibility scoring (demo/fallback)

module Dating
  class CompatibilityScorer
    def initialize(profile_a, profile_b)
      @profile_a = profile_a
      @profile_b = profile_b
    end

    def score
      if ENV["LLM_COMPAT_ENABLED"] == "true" && defined?(RubyLLM)
        llm_score
      else
        heuristic_score
      end
    end

    private

    attr_reader :profile_a, :profile_b

    def heuristic_score
      shared = (profile_a.interests.to_a & profile_b.interests.to_a).size
      base = 40 + shared * 10
      base += 10 if profile_a.neighborhood == profile_b.neighborhood
      [base, 98].min
    end

    def llm_score
      prompt = "Rate compatibility 0-100 between profiles: #{profile_a.interests} and #{profile_b.interests}"
      response = RubyLLM.chat(prompt)
      response.to_s[/\d+/].to_i.clamp(0, 100)
    rescue StandardError
      heuristic_score
    end
  end
end