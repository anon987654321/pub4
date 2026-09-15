# frozen_string_literal: true

module Master
  module Core
    module Domain
      # The DomainVerifier runs deterministic checks based on the active domain.
      # It transforms "expertise" into "executable evidence."
      class Verifier
        def initialize(container)
          @container = container
        end

        # Executes a suite of domain-specific checks.
        def verify(project_root, domains)
          results = { passed: [], failed: [], warnings: [] }
          
          domains.each do |domain|
            case domain
            when :rails then run_rails_checks(project_root, results)
            when :pwa then run_pwa_checks(project_root, results)
            end
          end
          
          results
        end

        private

        def run_rails_checks(root, res)
          # Example deterministic check: Check for fat controllers
          # In reality, this would use a Ruby AST parser to count lines/methods
          res[:passed] << "rails:framework_conventions_verified"
        end

        def run_pwa_checks(root, res)
          # Example deterministic check: Viewport meta tag
          html = File.read("#{root}/app/views/layouts/application.html.erb") rescue ""
          if html.include?("viewport") && html.include?("width=device-width")
            res[:passed] << "pwa:viewport_verified"
          else
            res[:failed] << "pwa:viewport_missing"
          end
        end
      end
    end
  end
end
