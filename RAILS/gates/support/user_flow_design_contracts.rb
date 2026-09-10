# frozen_string_literal: true

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
            # Intentional exceptions: yep.com pen (.search.focus box-shadow) and
            # jOxVvNE carbon-example — documented product pens. Flag elsewhere.
            forbidden: /box-shadow\s*:\s*(?!none\b)|text-shadow\s*:|backdrop-filter\s*:|filter\s*:[^;]*\bblur\(/i,
            allow_path: %r{(search_yep|jsfiddle_chrome|_marketplace_nav_bar|_marketplace_animated_logo)\.scss\z},
          },
          {
            id: :vertical_accent_single_map,
            principle: "consistency / design_tokens exact_token_use",
            meaning: "Vertical accents only from design_tokens / _vertical_shell",
            paths: %w[brgen/app/assets/stylesheets],
            # Local sheets must not re-assign --accent except shell
            forbidden_in: {
              glob: "_vertical_*.scss",
              pattern: /--accent\s*:/,
              allow_file: /_vertical_shell\.scss\z/,
            },
          },
          {
            id: :touch_target_buy_bar,
            principle: "fitts_law / touch target_min_px 44",
            meaning: "Sticky buy bar CTAs declare min-height 44px",
            # Was brgen/app/assets/stylesheets/_marketplace.scss, which has not held
            # the buy bar since the verticals became mountable engines — the same
            # blind spot that cost four other scanners 57 views. It also read
            # `required_any: [44px literal, listing-buy-bar]`, so a sheet merely
            # mentioning the class satisfied a rule about touch geometry, and the
            # literal no longer matches a tree that spells the floor var(--tap-min).
            # Both halves are required now, against the file that actually styles it.
            paths: %w[brgen/engines/marketplace/app/assets/stylesheets/_vertical_marketplace.scss],
            required_all: [/\.listing-buy-bar-cta/, /min-height:\s*(?:44px|var\(--tap-min\))/],
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
            ],
            scope_glob: "**/payments/**/*.rb",
          },
        ]
      end

      def design_contract_checks
        design_contracts.each { |contract| apply_design_contract(contract) }
        # WIRING_NOTES flat rule still the product constitution for non-pen CSS
        if File.file?(WIRING_NOTES)
          notes = File.read(WIRING_NOTES)
          @result.fail("user_flow: WIRING_NOTES lost Flat rule") unless notes.match?(/Flat rule|box-shadow/i)
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
        if contract[:forbidden_in]
          spec = contract[:forbidden_in]
          Dir.glob(File.join(dir, "**", spec[:glob])).each do |path|
            next if spec[:allow_file] && path.match?(spec[:allow_file])

            body = File.read(path)
            if body.match?(spec[:pattern])
              @result.fail("#{label}: #{path.sub(RAILS_ROOT + '/', '')} reassigns vertical accent (use _vertical_shell only)")
            end
          end
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

          body = File.read(path)
          if body.match?(contract[:forbidden])
            @result.fail("#{label}: forbidden pattern in #{path.sub(RAILS_ROOT + '/', '')}")
          end
        end
      end

      def scan_file_contract(path, rel, contract, label)
        body = File.read(path)
        Array(contract[:required_all]).each do |pat|
          @result.fail("#{label}: #{rel} missing #{pat.inspect}") unless body.match?(pat)
        end
        if contract[:required_any]
          unless contract[:required_any].any? { |pat| body.match?(pat) }
            @result.fail("#{label}: #{rel} missing any of #{contract[:required_any].map(&:inspect).join(', ')}")
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
