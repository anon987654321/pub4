# frozen_string_literal: true

module Master
  module Ground
  module ClaudeCodeTasks
  module MobileWebClusters
    GOAL = "Make MASTER generate, refactor, and redesign Rails 8 mobile-first PWAs."

    PRIMARY_CAPABILITY = {
      name: :rails_8_mobile_first_pwa_operator,
      purpose: "Turn user goals or existing Rails apps into mobile-first Rails 8 + Hotwire + PWA implementations.",
      modes: %i[generate_from_blank refactor_existing redesign_ui audit_pwa mine_reference_repos],
      default_stack: %i[rails_8 hotwire turbo stimulus solid_queue solid_cache solid_cable importmap pwa_manifest service_worker],
      design_default: :mobile_first_content_first,
      output_style: :ruby_runtime_policy_not_markdown
    }.freeze

    RAILS_8_PWA_TASKS = {
      generate_from_blank: [
        "Create a Rails 8 app plan using omakase defaults before adding extras.",
        "Generate mobile-first routes, controllers, models, views, Turbo Frames, Turbo Streams, and Stimulus controllers.",
        "Add manifest, service worker registration, offline fallback, icon policy, and installability checks.",
        "Use progressive enhancement: core app works without JavaScript, Hotwire upgrades behavior.",
        "Produce semantic HTML, accessible forms, keyboard navigation, and touch targets >= 44px."
      ],
      refactor_existing: [
        "Detect Rails 8, Hotwire, Stimulus, ViewComponent, Solid Queue/Cache/Cable, PWA, and importmap/jsbundling state.",
        "Replace jQuery/UJS/AJAX fragments with Turbo Frames, Turbo Streams, and small Stimulus controllers.",
        "Consolidate ERB partial sprawl into cohesive components only when reuse or complexity justifies it.",
        "Simplify divitis into semantic HTML landmarks and mobile-first content flow.",
        "Preserve user content and behavior; make reversible commits/checkpoints before invasive refactors."
      ],
      redesign_ui: [
        "Apply mobile-first layout: single-column baseline, responsive enhancement, bottom-safe primary actions when appropriate.",
        "Use content-first brutal/minimal profile unless the app domain requires richer visual identity.",
        "Enforce readable typography: 45-75ch line length, body line-height >= 1.5, body font >= 16px.",
        "Respect prefers-reduced-motion and avoid decorative animation by default.",
        "Audit contrast, focus states, landmarks, form labels, error messages, and touch target size."
      ],
      audit_pwa: [
        "Check manifest completeness, icons, theme/background colors, display mode, start_url, and scope.",
        "Check service worker strategy: no private chat/auth content cached by default.",
        "Add offline shell/fallback only after privacy-safe cache policy is explicit.",
        "Check network failure UX, background sync candidates, and install prompt timing.",
        "Record Lighthouse/PWA/accessibility/performance findings as Ruby audit objects."
      ],
      mine_reference_repos: [
        "Mine GitHub repos only to extract reusable Rails/mobile/PWA patterns.",
        "Do not implement mined patterns blindly; rank by maintenance, license, simplicity, and fit.",
        "Record candidate repos in Ruby catalog with why, extractable pattern, and risk.",
        "Prefer Rails 8, Hotwire, Turbo Native, PWA, offline-first, local-first, and mobile web repos."
      ]
    }.freeze

    GITHUB_MINING_AREAS = {
      rails_8_pwa: {
        queries: [
          "Rails 8 PWA Hotwire service worker",
          "Rails Hotwire PWA mobile first",
          "Rails 8 mobile first Turbo Stimulus app"
        ],
        extract: %i[manifest service_worker hotwire_layout mobile_navigation offline_policy]
      },
      hotwire_mobile: {
        queries: [
          "Turbo Native Rails mobile app Hotwire",
          "Rails Hotwire mobile bottom navigation",
          "Stimulus mobile gestures Rails"
        ],
        extract: %i[turbo_native_bridge stimulus_controllers mobile_nav gesture_policy]
      },
      offline_local_first_rails: {
        queries: [
          "Rails offline first PWA IndexedDB sync",
          "Rails local first sync Hotwire",
          "Rails service worker background sync PWA"
        ],
        extract: %i[indexeddb_queue sync_conflict_model background_sync privacy_cache]
      },
      rails_ui_refactor: {
        queries: [
          "Rails partials to ViewComponent Hotwire",
          "Rails jQuery to Stimulus Turbo refactor",
          "Rails semantic HTML accessibility mobile first"
        ],
        extract: %i[partial_consolidation component_boundary stimulus_refactor accessibility_rules]
      }
    }.freeze

    REQUIRED_NEW_RUBY = %w[
      lib/rails/mobile_pwa_operator.rb
      lib/rails/rails8_app_audit.rb
      lib/rails/hotwire_refactor_policy.rb
      lib/rails/pwa_audit.rb
      lib/design/mobile_first_pwa_profiles.rb
      lib/ground/repo_mining/mobile_web_cluster_catalog.rb
    ].freeze

    REQUIRED_INTEGRATIONS = {
      "lib/ground/intent_router.rb" => [
        "map 'generate rails pwa', 'refactor rails app', and 'redesign mobile pwa' to Rails PWA intents"
      ],
      "lib/judge/council/ui_critique.rb" => [
        "include mobile-first Rails PWA profile in UI critique when Rails/web files are present"
      ],
      "lib/ground/context_provider.rb" => [
        "select Rails app files, routes, views, controllers, Stimulus controllers, manifest, and service worker for Rails PWA tasks"
      ],
      "lib/now/cli.rb" => [
        "add /rails-pwa-audit command after operator CLI wiring exists"
      ]
    }.freeze

    CONSTRAINTS = [
      "No markdown deliverables.",
      "MASTER must generate, refactor, and redesign Rails 8 mobile-first PWAs as executable repo work.",
      "Use Rails conventions first; add gems/frameworks only when justified.",
      "Hotwire/Turbo/Stimulus are preferred over SPA rewrites.",
      "Do not cache private/authenticated content in service worker by default.",
      "Every generated/refactored UI must be accessible, keyboard-operable, touch-safe, and responsive from 320px upward.",
      "Every large refactor must checkpoint before mutation and verify after mutation.",
      "Repo mining is support input; Rails 8 mobile-first PWA generation/refactor/redesign is the primary capability."
    ].freeze

    VERIFY = [
      "ruby -c MASTER/lib/rails/mobile_pwa_operator.rb",
      "ruby -c MASTER/lib/rails/rails8_app_audit.rb",
      "ruby -c MASTER/lib/rails/hotwire_refactor_policy.rb",
      "ruby -c MASTER/lib/rails/pwa_audit.rb",
      "ruby -c MASTER/lib/design/mobile_first_pwa_profiles.rb",
      "ruby -c MASTER/lib/ground/repo_mining/mobile_web_cluster_catalog.rb",
      "grep -R \"rails_8_mobile_first_pwa_operator\|generate_from_blank\|refactor_existing\|redesign_ui\" MASTER/lib/rails MASTER/lib/design MASTER/lib/ground",
      "grep -R \"do not cache private\|Hotwire\|Turbo\|Stimulus\" MASTER/lib/rails MASTER/lib/design MASTER/lib/ground"
    ].freeze
  end
  end
  end
end
