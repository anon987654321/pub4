# frozen_string_literal: true

require_relative "../../tools/design/scss_rules"
require_relative "../../tools/design/frontend_rule_set"

module Deploy
  class UserFlowGate
    # The MASTER design contracts, and the source reader that judges them: a
    # table of conceptual rules — flat surfaces, Stimulus over jQuery, honest
    # payment failure, a skip link, one h1, one accent map, a 44px buy bar —
    # each paired with the paths and patterns that make it detectable.
    #
    # Split out of user_flow.rb, whose own header admitted to being two gates
    # in one: "critical-path user flows + MASTER design/principle semantics".
    # None of this is a user flow. It never opens a socket, never asks whether
    # an app is up, and would give the same answer on a tree with no apps
    # booted at all. What stays behind walks the critical paths.
    #
    # A module included back into the gate, like ContrastChecks in the geometry
    # gate, so it keeps @result and the gate's own idea of where the tree is.
    #
    # The table is a method rather than a frozen constant for one reason: it
    # reads VIEW_PATHS, which the gate class builds in its own body, and this
    # file is required before that body runs. A constant here would capture
    # nothing — the same load-order trap as a path built from __dir__, which
    # broke the design_metrics split twice. Resolved at call time, it holds
    # wherever the file sits.
    module DesignContracts
      # Three groups, by what a contract reads rather than by what it means: the
      # stylesheet contracts open .scss, the markup contracts open layouts and
      # views, and the payment one opens Ruby services. One list of seven was the
      # longest method in the gates tree, and a list is the one thing that grows
      # without anyone deciding it should.
      def design_contracts
        @design_contracts ||= (stylesheet_contracts + markup_contracts + payment_contracts).freeze
      end

      def stylesheet_contracts
        [
          {
            id: :flat_ui,
            principle: "flat_ui / rejection_of_ornament",
            meaning: "Separation via borders/surfaces, not shadows or blur",
            paths: %w[
              brgen/app/assets/stylesheets
              amber/app/assets/stylesheets
              bsdports/app/assets/stylesheets
              shared/app/assets/stylesheets
            ],
            # Intentional exceptions are the documented product pens — the yep.com
            # search, jOxVvNE, Amazon's nav bar and logo — read with their rules
            # blanked. Flag everything else.
            forbidden: /box-shadow\s*:\s*(?!none\b)|text-shadow\s*:|backdrop-filter\s*:|filter\s*:[^;]*\bblur\(/i,
            allow_path: Shared::FrontendRuleSet::PRODUCT_PEN_FILES,
            without_pens: true,
          },
          {
            id: :vertical_accent_single_map,
            principle: "consistency / design_tokens exact_token_use",
            meaning: "Vertical accents only from design_tokens, through brgen's accent map",
            paths: %w[brgen/app/assets/stylesheets],
            # No rule re-assigns --accent except the @each over $vertical-accents.
            forbidden_rule: {
              declares: /(?<![\w-])--accent\s*:/,
              unless_within: /\A@each\b.*\$vertical-accents\b/,
            },
          },
          {
            id: :touch_target_buy_bar,
            principle: "fitts_law / touch target_min_px 44",
            meaning: "Sticky buy bar CTAs declare min-height 44px",
            # The rule styling the CTA has to carry the floor itself. A sheet that
            # merely mentions the class, or declares 44px for something else,
            # satisfied the file-scoped version of this contract.
            paths: %w[brgen/app/assets/stylesheets/application.scss],
            required_rule: [/\.listing-buy-bar-cta\b/, /min-height:\s*(?:44px|var\(--tap-min\))/],
          },
        ]
      end

      def markup_contracts
        [
          {
            id: :stimulus_progressive,
            principle: "stimulus_progressive / progressive_enhancement",
            meaning: "Behavior via Stimulus data-controller, not jQuery CDN apps",
            paths: VIEW_PATHS,
            forbidden: /jquery(\.min)?\.js|cdn\.jsdelivr\.net\/npm\/jquery/i,
            allow_path: nil,
          },
          {
            id: :skip_to_main,
            principle: "accessibility / SKIP_TO_MAIN",
            meaning: "Every app layout has skip link to #main-content",
            paths: %w[
              brgen/app/views/layouts/application.html.erb
              amber/app/views/layouts/application.html.erb
              bsdports/app/views/layouts/application.html.erb
            ],
            required_all: [/#main-content/, /skip-link|Skip to main/i],
          },
          {
            id: :single_h1_marketplace_listings,
            principle: "hierarchy / clarity",
            meaning: "Marketplace listings index exposes exactly one document h1",
            paths: %w[brgen/engines/marketplace/app/views/marketplace/listings/index.html.erb],
            required_all: [/<h1\b/i],
            max_h1: 1,
          },
        ]
      end

      def payment_contracts
        [
          {
            id: :fail_visibly_payments,
            principle: "fail_fast / good_design_is_honest",
            meaning: "Checkout without keys must not pretend payment succeeded",
            paths: %w[brgen/app],
            required_any: [
              /NotConfigured|not configured|payment not configured|STRIPE_SECRET|VIPPS_.*KEY/i,
              # A file may satisfy this by delegating rather than by spelling it.
              # stripe_refund.rb opens submit! with StripeCheckout.ensure!, which
              # raises NotConfigured when the key is absent -- so it is fail-closed,
              # and it named none of the words above. That is the shape CLAUDE.md
              # records for the dead-file census that searched for context_provider
              # while every caller wrote the constant: a detector that only reads the
              # inline spelling reports the abstraction as the defect.
              #
              # Tight on purpose. It wants a call to a named guard on a constant, in
              # a scope that is payments services only, where ensure! is the
              # convention. Measured: it moves stripe_refund.rb and no other file.
              /(?:^|\s)[A-Z]\w*\.ensure!/,
              # Two more fail-closed shapes, each a secret the file cannot work
              # without: ENV.fetch with no default raises when the secret is
              # absent (dintero_client.rb authenticates that way), and a
              # verifier that answers false when its secret is blank accepts
              # nothing (dintero_signature.rb). Measured: these move those two
              # files and no other.
              /ENV\.fetch\(\s*"[A-Z_]*SECRET"\s*\)/,
              /return false if ENV\["[A-Z_]*SECRET"\]\.to_s\.blank\?/,
            ],
            scope_glob: "**/payments/**/*.rb",
            # A file that defines no method performs no payment, so it cannot
            # pretend one succeeded. provider_error.rb is a one-line exception
            # class and was failing a contract it has no way to break.
            performs_only_if: /^\s*def\s/,
          },
        ]
      end

      def design_contract_checks
        design_contracts.each { |contract| apply_design_contract(contract) }
        # The flat rule in shared/README.md is the product constitution for non-pen CSS.
        if File.file?(DESIGN_DOC)
          notes = File.read(DESIGN_DOC)
          @result.fail("user_flow: shared/README.md lost the Flat rule") unless notes.match?(/Flat rule|box-shadow/i)
        end
      end

      def apply_design_contract(contract)
        label = "design:#{contract[:id]} (#{contract[:principle]})"
        Array(contract[:paths]).each do |rel|
          @result.checked!
          abs = File.join(RAILS_ROOT, rel)
          unless File.exist?(abs)
            # Payment files may not exist yet — warn so flow gate still teaches the contract
            if contract[:id] == :fail_visibly_payments
              @result.warn("#{label}: payment paths not present yet — create honest NotConfigured stubs")
              next
            end
            @result.fail("#{label}: missing path #{rel}")
            next
          end

          if File.directory?(abs)
            scan_directory_contract(abs, contract, label)
          else
            scan_file_contract(abs, rel, contract, label)
          end
        end
      end

      def scan_directory_contract(dir, contract, label)
        if contract[:forbidden_rule]
          Dir.glob(File.join(dir, "**/*.scss")).each { |path| scan_forbidden_rules(path, contract, label) }
        end

        if contract[:scope_glob]
          files = Dir.glob(File.join(dir, contract[:scope_glob]))
          if files.empty? && contract[:required_any]
            @result.warn("#{label}: no files match #{contract[:scope_glob]}")
            return
          end
          files.each { |path| scan_file_contract(path, path.sub(RAILS_ROOT + "/", ""), contract, label) }
          return
        end

        return unless contract[:forbidden]

        Dir.glob(File.join(dir, "**/*.{scss,css,erb,js,html}")).each do |path|
          next if contract[:allow_path] && path.match?(contract[:allow_path])

          if contract_body(path, contract).match?(contract[:forbidden])
            @result.fail("#{label}: forbidden pattern in #{path.sub(RAILS_ROOT + '/', '')}")
          end
        end
      end

      def scan_forbidden_rules(path, contract, label)
        spec = contract[:forbidden_rule]
        Operator::ScssRules.rules(File.read(path)).each do |rule|
          next unless rule.declares?(spec[:declares])
          next if rule.parents.any? { |parent| parent.match?(spec[:unless_within]) }

          @result.fail("#{label}: #{path.sub(RAILS_ROOT + '/', '')}:#{rule.line} #{rule.selector} " \
                       "reassigns vertical accent (use the accent map only)")
        end
      end

      # A stylesheet read for a hygiene pattern is read with its product pens
      # blanked, when the contract says pens are exempt.
      def contract_body(path, contract)
        body = File.read(path)
        return body unless contract[:without_pens] && path.match?(/\.s?css\z/)

        Operator::ScssRules.without(body, Shared::FrontendRuleSet::PRODUCT_PEN_SELECTORS)
      end

      def scan_file_contract(path, rel, contract, label)
        body = contract_body(path, contract)
        return if contract[:performs_only_if] && !body.match?(contract[:performs_only_if])

        Array(contract[:required_all]).each do |pat|
          @result.fail("#{label}: #{rel} missing #{pat.inspect}") unless body.match?(pat)
        end
        if contract[:required_any]
          unless contract[:required_any].any? { |pat| body.match?(pat) }
            @result.fail("#{label}: #{rel} missing any of #{contract[:required_any].map(&:inspect).join(', ')}")
          end
        end
        if contract[:required_rule]
          selector, declaration = contract[:required_rule]
          unless Operator::ScssRules.matching(body, selector).any? { |rule| rule.declares?(declaration) }
            @result.fail("#{label}: #{rel} has no #{selector.inspect} rule declaring #{declaration.inspect}")
          end
        end
        if contract[:max_h1]
          count = body.scan(/<h1\b/i).size
          @result.fail("#{label}: #{rel} has #{count} h1 tags (max #{contract[:max_h1]})") if count > contract[:max_h1]
        end
        if contract[:forbidden] && !(contract[:allow_path] && path.match?(contract[:allow_path]))
          @result.fail("#{label}: forbidden pattern in #{rel}") if body.match?(contract[:forbidden])
        end
      end
    end
  end
end
