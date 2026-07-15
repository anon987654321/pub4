# frozen_string_literal: true

module Master
  module Ground
    class IntentRouter
      INTENTS = {
        codify_policy: %w[codify policy make it ruby turn into],
        refactor_to_ruby: %w[refactor move ruby extract simplify],
        wire_existing_module: %w[wire connect hook up route plug],
        create_facade: %w[facade wrap adapter interface],
        delete_redundant_config: %w[delete remove kill purge drop],
        verify_patch_landed: %w[verify check confirm did it land],
        run_sound_review: %w[sound review audio critique listen],
        run_ui_review: %w[ui critique design visual look review],
        generate_rails_pwa: %w[generate create new rails pwa app scaffold blank],
        refactor_rails_app: %w[refactor upgrade migrate modernize rails hotwire turbo stimulus],
        redesign_mobile_pwa: %w[redesign mobile touch layout responsive accessibility],
        audit_rails_pwa: %w[audit scan check pwa manifest service worker rails],
        apply_user_style_rules: %w[style format lint clean],
        continue_prior_plan: %w[go ahead continue land it proceed ship],
        write_repo_changes: %w[land write commit save push apply],
        prefer_ruby: %w[ruby not markdown no yaml keep ruby],
        run_full_workflow: %w[through master tribunal full pass review deliberate deliberation deliberating deliberations],
      }.freeze

      STANDING_SEMANTICS = {
        "go ahead" => :continue_prior_plan,
        "land it" => :write_repo_changes,
        "codify" => :codify_policy,
        "wire" => :wire_existing_module,
        "verify" => :verify_patch_landed,
        "yes" => :continue_prior_plan,
        "ship" => :write_repo_changes,
        "proceed" => :continue_prior_plan,
      }.freeze

      RISK_TIERS = {
        low: %i[
          codify_policy refactor_to_ruby create_facade apply_user_style_rules
          run_sound_review run_ui_review audit_rails_pwa generate_rails_pwa redesign_mobile_pwa
        ],
        medium: %i[wire_existing_module verify_patch_landed continue_prior_plan prefer_ruby refactor_rails_app run_full_workflow],
        high: %i[write_repo_changes delete_redundant_config],
        critical: [],
      }.freeze

      def classify(text)
        downcased = text.to_s.downcase.strip
        return STANDING_SEMANTICS[downcased] if STANDING_SEMANTICS.key?(downcased)

        # Exact token match, not substring/prefix: short keywords like "ui",
        # "go", "no", "up" are common word PREFIXES too ("norwegian" starts
        # with "no", "quick" contains "ui" anywhere) and either weaker check
        # misroutes plain chat into the coding Fold. Every INTENTS keyword is
        # a real whole word (we spell out inflections like "deliberating"
        # explicitly above) so exact match is correct, not safer alone.
        tokens = downcased.scan(/\w+/)
        scores = INTENTS.transform_values do |keywords|
          tokens.count { |t| keywords.include?(t) }
        end
        best, score = scores.max_by { |_, v| v }
        score.positive? ? best : :unknown
      end

      def risk(intent)
        RISK_TIERS.each { |tier, intents| return tier if intents.include?(intent) }
        :medium
      end

      def route(text)
        intent = classify(text)
        { intent: intent, risk: risk(intent) }
      end
    end
  end
end
