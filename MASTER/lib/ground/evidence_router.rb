# frozen_string_literal: true

module Master
  module Ground
    module EvidenceRouter
      MODES = %i[conversation repository web_current deep_research browser device unknown].freeze

      CURRENT = /\b(?:latest|current|today|tonight|now|recent|recently|this\s+(?:week|month|year)|as\s+of|newest|up[-\s]?to[-\s]?date|20\d{2})\b/i
      RESEARCH = /\b(?:research|investigate|deep\s+dive|look\s+into|study|compare\s+(?:sources|options|approaches)|survey|literature|find\s+out)\b/i
      # %r{} because the path class holds a literal slash.
      REPOSITORY = %r{\b(?:repo(?:sitory)?|codebase|code|file|files|module|class|method|gemfile|rails|master|git|commit|branch|diff|source)\b|(?:^|\s)[\w./-]+\.(?:rb|yml|yaml|json|md|js|mjs|ts|tsx|erb|css|scss|sh|zsh)\b}i
      BROWSER = /\b(?:browser|web\s+page|navigate|click|log\s+in|login|open\s+(?:the\s+)?(?:site|website|page)|inspect\s+(?:the\s+)?(?:site|page|account)|onlyfans|fetlife|snapchat\s+account|telegram\s+account|whatsapp\s+account)\b/i
      # An account on one of these is the governed social_browser's work; any other site is a
      # page to render. Kept apart so a shopping request never runs a social-account preflight.
      SOCIAL_ACCOUNTS = /\b(?:onlyfans|fetlife|snapchat\s+account|telegram\s+account|whatsapp\s+account)\b/i
      # A named site (a URL, or a bare domain) plus something to do there. File names such as
      # foo.rb or notes.md do not end in a registrable TLD, so they stay repository questions.
      SITE = %r{\bhttps?://\S+|\bwww\.\S+|\b[a-z0-9][a-z0-9-]*\.(?:com|net|org|io|co|app|shop|store|no|se|dk|de|uk|fr|nl|eu)\b}i
      SITE_INTENT = /\b(?:find|look(?:ing)?|search|browse|check|open|see|show|get|buy|price|prices|cheap(?:est)?|compare|reviews?|listings?|products?|deals?|order|what'?s\s+on)\b/i
      DEVICE = /\b(?:android|termux|wifi|wi-?fi|bluetooth|sensor|camera|microphone|battery|torch|location|device)\b/i
      CONVERSATION = /\A(?:hi|hello|hey|thanks?|thank\s+you|good\s+(?:morning|evening|night)|how\s+are\s+you)[!?.,\s]*\z/i

      RESEARCH_PROMPT = "Evidence rule: when a question is current, niche, uncertain, "                        "or externally verifiable, do not answer from memory. Use the "                        "available knowledge or web tools first, then separate observed "                        "evidence from inference."

      module_function

      def classify(text)
        value = text.to_s.strip
        return :conversation if value.match?(CONVERSATION)
        return :browser if value.match?(SITE) && value.match?(SITE_INTENT)
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
          "Capability rule: this turn concerns a website. You do have a browser. For a page you only need to read " \
          "(a shop, a listing, a JavaScript site), call WebBrowse with the page URL; build the site's own search URL " \
          "yourself, and use WebFetch only for static pages, because a script-built page comes back from it as an " \
          "empty shell. Try WebBrowse before saying a site cannot be read; if the page shows a captcha, a login wall " \
          "or nothing useful, say exactly what it returned. Clicking, logging in and session state belong to the " \
          "governed browser plugins (social_browser, travel_browser)."
        when :device
          "Capability rule: this turn concerns local hardware. Use the governed device or wireless capability and report unavailable permissions or backends plainly."
        else
          RESEARCH_PROMPT
        end
      end
    end
  end
end
