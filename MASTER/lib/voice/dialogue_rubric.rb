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

      SUPPORT_CUES = %r{
        \b(?:
          overwhelmed|overwhelm|anxious|anxiety|panic|depress(?:ed|ion)|stress(?:ed)?|grief|lonely|loneliness
          |burned\s+out|burnt\s+out|ruminat(?:e|ing|ion)|trauma|therap(?:y|ist)|mental\s+health|psychiatr
          |cbt|dbt|act\s+therapy|adhd|autis(?:m|tic)|medication|antidepressant|antipsychotic|stimulant
          |psychotropic|prescription|ssri|snri|dose|psychiatrist|psychologist|suicid|self[- ]harm|hurt\s+myself
          |keep\s+myself\s+safe|can't\s+stay\s+safe|want\s+to\s+die|don't\s+want\s+to\s+live
          |do\s+not\s+want\s+to\s+live|overdos(?:e|ed)|hurt\s+someone|immediate\s+danger
          |unsafe\s+at\s+home|don't\s+feel\s+safe|do\s+not\s+feel\s+safe|threatened\s+me
          |hit\s+me|hitting\s+me|forced\s+me|afraid\s+of\s+my\s+partner|scared\s+of\s+my\s+partner
          |won't\s+let\s+me|doesn't\s+let\s+me|reads\s+my\s+messages|checks\s+my\s+phone
          |relationship|partner|boyfriend|girlfriend|husband|wife|couple|marriage|breakup|break\s+up
          |argument|fight\s+with|gaslight|manipulat|narcissis|abusive|coercive|controlling\s+me
          |boundaries|boundary|family\s+conflict|procrastinat(?:e|ion)|motivation|anger|angry|resentment|shame|guilt
          |social\s+anxiety|sleep\s+problems|can't\s+stop\s+thinking|cannot\s+stop\s+thinking
          |keep\s+replaying|i\s+feel\s+(?:sad|stuck|empty|hopeless|anxious|angry|overwhelmed|unsafe|lost)
          |i(?:'m|\s+am)\s+struggling|i\s+can't\s+cope|i\s+cannot\s+cope
          |i\s+need\s+advice|need\s+personal\s+advice|personal\s+problem|help\s+me\s+think\s+through
          |help\s+me\s+work\s+through|talk\s+this\s+through|having\s+a\s+hard\s+time
          |i\s+don't\s+know\s+what\s+to\s+do|i\s+do\s+not\s+know\s+what\s+to\s+do
          |someone\s+in\s+my\s+life|friendship|my\s+friend|my\s+boss|coworker|colleague
          |workplace\s+bullying|bullying|humiliat\w*
          |psykisk\s+helse|sliter|angst|angstlidelse|deprimert|depresjon|panikk|stresset|ensom|ensomhet
          |sorg|utbrent|tankekjør|grubler|traume|terapi|terapeut|psykiatri|medisin|medisiner|antidepressiva
          |psykose|mani|selvmord|selvmordstanker|selvskading|skade\s+meg\s+selv|vil\s+dø|vil\s+ikke\s+leve
          |orker\s+ikke\s+mer|klarer\s+ikke\s+(?:å\s+)?holde\s+meg\s+trygg|fare\s+for\s+liv
          |føler\s+meg\s+(?:trist|fastlåst|tom|håpløs|engstelig|sint|overveldet|utrygg|fortapt)
          |jeg\s+(?:sliter|trenger\s+hjelp|trenger\s+råd|vet\s+ikke\s+hva\s+jeg\s+skal\s+gjøre)
          |jeg\s+har\s+det\s+vanskelig|jeg\s+klarer\s+ikke|trenger\s+personlige\s+råd
          |forhold|partner|kjæreste|samboer|ektefelle|ekteskap|parforhold|krangel|krangler|skilsmisse
          |intimitet|familiekonflikt|gaslighting|manipulasjon|narsissist|psykisk\s+vold|kontrollerer\s+meg
          |sjekker\s+(?:mobilen|telefonen)|sporer\s+(?:mobilen|telefonen)|truer\s+meg|slår\s+meg
          |tvinger\s+meg|holder\s+meg\s+isolert|kontrollerer\s+(?:økonomien|pengene\s+mine)
          |leser\s+meldingene\s+mine|kaller\s+meg\s+gal|sier\s+at\s+jeg\s+er\s+gal
          |grenser|familiekonflikt|utsetter|prokrastinerer|motivasjon|sinne|skam|skyld|vennskap
          |vennen\s+min|sjefen\s+min|kollega|mobbing|ydmyker\s+meg|kampkunst|kampsport|meditasjon
          |tankefullt\s+nærvær|zen|tai\s+chi|aikido|budo|mestring
        )\b
      }ix.freeze

      RELATIONSHIP_CUES = %r{
        \b(?:relationship|partner|boyfriend|girlfriend|husband|wife|couple|marriage|breakup|break\s+up
        |argument|fight\s+with|dating|intimacy|divorce|family\s+conflict|forhold|partner|kjæreste
        |samboer|ektefelle|ekteskap|parforhold|krangel|krangler|skilsmisse|intimitet|familiekonflikt)\b
      }ix.freeze

      MANIPULATION_CUES = %r{
        \b(?:gaslight|manipulat|narcissis|abusive|coercive|controlling\s+me|surveillance|stalking
        |threat(?:en|s|ening)?|threatened\s+me|hit\s+me|hitting\s+me|forced\s+me|calls\s+me\s+crazy
        |says\s+i\s+am\s+crazy|says\s+i'm\s+crazy|isolation|financial\s+control|controls\s+my\s+money
        |checks\s+my\s+phone|reads\s+my\s+messages|demands\s+my\s+password|tracks\s+my\s+phone
        |monitors\s+me|won't\s+let\s+me|doesn't\s+let\s+me|gaslighting|manipulasjon|narsissist
        |psykisk\s+vold|kontrollerer\s+meg|sjekker\s+(?:mobilen|telefonen)|sporer\s+(?:mobilen|telefonen)
        |truer\s+meg|slår\s+meg|tvinger\s+meg|holder\s+meg\s+isolert
        |kontrollerer\s+(?:økonomien|pengene\s+mine)|leser\s+meldingene\s+mine|kaller\s+meg\s+gal
        |sier\s+at\s+jeg\s+er\s+gal|nekter\s+meg\s+å)\b
      }ix.freeze

      MARTIAL_CUES = %r{
        \b(?:martial\s+arts|mindfulness|meditat(?:e|ion)|stoic(?:ism)?|zen|tai\s+chi|aikido|budo
        |qi\s+gong|kung\s+fu|karate|judo|taekwondo|non[- ]?attachment|kampkunst|kampsport|meditasjon)\b
      }ix.freeze

      CRISIS_CUES = %r{
        \b(?:suicid(?:e|al)|kill\s+myself|end\s+my\s+life|want\s+to\s+die|don't\s+want\s+to\s+live
        |do\s+not\s+want\s+to\s+live|can't\s+keep\s+myself\s+safe|cannot\s+keep\s+myself\s+safe
        |(?:don't|do\s+not)\s+think\s+i\s+can\s+keep\s+myself\s+safe|not\s+sure\s+i\s+can\s+keep\s+myself\s+safe
        |can't\s+stay\s+safe|hurt\s+myself|self[- ]harm|overdos(?:e|ed)|hurt\s+someone
        |going\s+to\s+hurt\s+someone|immediate\s+danger|selvmord|selvmordstanker|vil\s+ta\s+livet\s+mitt
        |ta\s+livet\s+mitt|vil\s+dø|vil\s+ikke\s+leve|orker\s+ikke\s+mer
        |klarer\s+ikke\s+(?:å\s+)?holde\s+meg\s+trygg|skade\s+meg\s+selv|selvskading|vil\s+skade\s+noen
        |fare\s+for\s+liv|akutt\s+fare)\b
      }ix.freeze

      RESEARCH_CUES = %r{
        \b(?:research|studies|evidence|clinical\s+guideline|systematic\s+review|meta-analysis|meta\s+analysis
        |scientific\s+evidence|papers|citations|sources|forskning|studier|dokumentasjon|evidens
        |systematisk\s+oversikt|meta-analyse|retningslinjer|kilder|referanser)\b
      }ix.freeze

      CLINICAL_DETAIL_CUES = %r{
        \b(?:depress(?:ed|ion)|psychiatr|diagnos(?:e|is|tic)|medication|antidepressant|bipolar|psychosis|mania
        |adhd|autis(?:m|tic)|ptsd|ocd|panic\s+disorder|therapy\s+options|treatment\s+options|side\s+effects
        |mental\s+health\s+professional|depresjon|psykiatri|diagnose|medisin|antidepressiva|bipolar
        |psykose|mani|autisme|panikklidelse|behandling|bivirkninger|psykolog|psykisk\s+helsepersonell)\b
      }ix.freeze

      def prompt_block(root: Master::ROOT)
        items = data(root:).fetch("dimensions", {})
        return if items.empty?

        lines = items.map { |name, item| "- #{name}: #{item.fetch("rule")}" }
        <<~XML.strip
          <master_dialogue_rubric>
          Conversation law:
          #{lines.join("\n")}
          Lead with substance. Calibrate certainty to evidence. Disagree when a claim is wrong or a plan is weak, and give the reason. Repair ambiguity plainly. Do not use canned assistant openers.
          </master_dialogue_rubric>
        XML
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "dialogue_rubric.prompt_block", severity: :cosmetic)
        nil
      end

      # The full clinical protocol is injected only when the current message
      # indicates that personal support is relevant, never into every coding turn.
      def support_prompt_for(message, root: Master::ROOT)
        text = message.to_s
        return if text.empty? || !text.match?(SUPPORT_CUES)

        support = data(root:).fetch("support_practice")
        areas = %w[response_contract clinical_methods evidence_and_research crisis_and_referral]
        areas << "relationship_safety" if text.match?(RELATIONSHIP_CUES)
        areas << "manipulation_resilience" if text.match?(MANIPULATION_CUES)
        areas.concat(%w[relationship_safety manipulation_resilience]) if text.match?(CRISIS_CUES)
        areas << "martial_and_contemplative_practice" if text.match?(MARTIAL_CUES)
        include_sources = text.match?(RESEARCH_CUES) || text.match?(CLINICAL_DETAIL_CUES) || text.match?(CRISIS_CUES)

        support_practice_block(support, areas: areas.uniq, include_sources:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "dialogue_rubric.support_prompt_for", severity: :cosmetic)
        nil
      end

      def support_practice_block(support, areas:, include_sources: false)
        lines = [support.fetch("activation")]
        sections = {
          "response_contract" => "Practical response",
          "clinical_methods" => "Clinical skills",
          "relationship_safety" => "Couples and relationship safety",
          "manipulation_resilience" => "Manipulation resistance",
          "martial_and_contemplative_practice" => "Martial and contemplative practice",
          "evidence_and_research" => "Evidence and research",
          "crisis_and_referral" => "Crisis and referral",
        }
        sections.each do |key, label|
          next unless areas.include?(key)

          items = Array(support[key]).map { |item| item.to_s.strip }.reject(&:empty?)
          next if items.empty?

          lines << "#{label}:"
          lines.concat(items.map { |item| "- #{item}" })
        end

        sources = include_sources ? Array(support["research_sources"]) : []
        unless sources.empty?
          lines << "Research starting points — open current sources and verify relevance before citing:"
          sources.each do |source|
            lines << "- #{source.fetch("name")}: #{source.fetch("url")} — #{source.fetch("use")}"
          end
        end

        <<~XML.strip
          <master_support_practice>
          #{lines.join("\n")}
          </master_support_practice>
        XML
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

        support = payload["support_practice"]
        raise ArgumentError, "support practice missing" unless support.is_a?(Hash)
        support_keys = %w[
          activation response_contract clinical_methods relationship_safety manipulation_resilience
          martial_and_contemplative_practice evidence_and_research crisis_and_referral research_sources
          evaluation_scenarios
        ]
        missing_support = support_keys.select { |key| support[key].nil? }
        raise ArgumentError, "support practice sections missing: #{missing_support.join(", ")}" unless missing_support.empty?
        support_keys.reject { |key| %w[activation research_sources evaluation_scenarios].include?(key) }.each do |key|
          raise ArgumentError, "support practice #{key} empty" unless support[key].is_a?(Array) && support[key].any?
        end
        sources = support["research_sources"]
        raise ArgumentError, "support practice sources missing" unless sources.is_a?(Array) && sources.size >= 6
        sources.each do |source|
          raise ArgumentError, "support practice source missing field" unless %w[name url use].all? { |key| source[key].to_s.strip != "" }
          raise ArgumentError, "support practice source URL invalid" unless source["url"].to_s.match?(%r{\Ahttps://\S+\z})
        end
        scenarios = support["evaluation_scenarios"]
        raise ArgumentError, "support practice scenarios missing" unless scenarios.is_a?(Array) && scenarios.size >= 6
        scenario_ids = scenarios.map { |scenario| scenario["id"].to_s }
        raise ArgumentError, "support scenario ids missing or duplicated" unless scenario_ids.none?(&:empty?) && scenario_ids.uniq == scenario_ids
        scenarios.each do |scenario|
          raise ArgumentError, "support scenario missing user/must" if scenario["user"].to_s.empty? ||
                                                                         !scenario["must"].is_a?(Array) || scenario["must"].empty?
        end

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
