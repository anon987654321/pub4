# frozen_string_literal: true

module Master
  module Ground
    module EvidenceRouter
      MODES = %i[conversation repository web_current deep_research browser device unknown].freeze

      CURRENT = /\b(?:latest|current|today|tonight|now|recent|recently|this\s+(?:week|month|year)|as\s+of|newest|up[-\s]?to[-\s]?date|2026)\b/i
      RESEARCH = /\b(?:research|investigate|deep\s+dive|look\s+into|study|compare\s+(?:sources|options|approaches)|survey|literature|find\s+out)\b/i
      REPOSITORY = /\b(?:repo(?:sitory)?|codebase|code|file|files|module|class|method|gemfile|rails|master|git|commit|branch|diff|source)\b|(?:^|\s)[\w./-]+\.(?:rb|yml|yaml|json|md|js|mjs|ts|tsx|erb|css|scss|sh|zsh)\b/i
      BROWSER = /\b(?:browser|website|web\s+page|navigate|click|log\s+in|login|open\s+site|account\s+page|onlyfans|fetlife|snapchat|telegram|whatsapp)\b/i
      DEVICE = /\b(?:android|termux|wifi|wi-?fi|bluetooth|sensor|camera|microphone|battery|torch|location|device)\b/i
      CONVERSATION = /\A(?:hi|hello|hey|thanks?|thank\s+you|good\s+(?:morning|evening|night)|how\s+are\s+you)[!?.,\s]*\z/i

      RESEARCH_PROMPT = "Evidence rule: when a question is current, niche, uncertain, "                        "or externally verifiable, do not answer from memory. Use the "                        "available knowledge or web tools first, then separate observed "                        "evidence from inference."

      module_function

      def classify(text)
        value = text.to_s.strip
        return :conversation if value.match?(CONVERSATION)
        return :web_current if value.match?(CURRENT)
        return :deep_research if value.match?(RESEARCH)
        return :browser if value.match?(BROWSER)
        return :device if value.match?(DEVICE)
        return :repository if value.match?(REPOSITORY)
        return :unknown if value.match?(/\b(?:what|why|how|which|is|are|does|do|can|could)\b/i)

        :conversation
      end

      def web_required?(mode)
        %i[web_current deep_research].include?(mode)
      end

      def prompt_for(mode)
        case mode.to_sym
        when :web_current
          "#{RESEARCH_PROMPT} Freshness is required for this turn. Start with WebSearch; "           "fetch primary sources when the snippets are insufficient."
        when :deep_research
          "#{RESEARCH_PROMPT} This turn asks for research. Start with SearchKnowledge "           "when relevant, then WebSearch and WebFetch; compare independent sources before concluding."
        when :repository
          "Evidence rule: this turn concerns the repository. Read/search the actual files before making claims about its current state."
        when :browser
          "Capability rule: this turn concerns browser interaction. Use the governed browser capability when an actual page interaction is required; WebFetch is not a substitute for clicking or session state."
        when :device
          "Capability rule: this turn concerns local hardware. Use the governed device or wireless capability and report unavailable permissions or backends plainly."
        else
          RESEARCH_PROMPT
        end
      end
    end
  end
end
