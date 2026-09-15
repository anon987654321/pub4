# frozen_string_literal: true

module Master
  module Core
    module Domain
      # The DomainEngine manages specialized engineering doctrines.
      # It separates framework knowledge (Rails), platform knowledge (PWA),
      # and project knowledge (Brgen) into addressable, executable layers.
      class Engine
        attr_reader :active_domains

        def initialize(container)
          @container = container
          @active_domains = []
        end

        # Recognizes the application type and loads the relevant doctrine.
        def detect_and_load(project_root)
          domains = []
          
          # 1. Framework Detection (Rails)
          domains << :rails if File.exist?("#{project_root}/config/application.rb")
          
          # 2. Platform Detection (PWA)
          domains << :pwa if File.exist?("#{project_root}/public/manifest.json") || 
                             Dir.glob("#{project_root}/app/javascript/**/*service-worker*").any?
          
          # 3. Project-Specific Detection (Brgen/Amber)
          domains << :brgen if project_root.include?("brgen")
          domains << :amber if project_root.include?("amber")
          
          @active_domains = domains
          domains
        end

        # Retrieves the applicable doctrine for the current context.
        def doctrine_for(domain)
          # In a full implementation, this reads from MASTER/domains/<domain>/doctrine.yml
          # For now, it returns the semantic role of the domain.
          {
            domain: domain,
            priority: domain_priority(domain),
            expert_rules: domain_rules(domain)
          }
        end

        private

        def domain_priority(domain)
          { rails: 1, pwa: 2, brgen: 3, amber: 3 }[domain] || 10
        end

        def domain_rules(domain)
          case domain
          when :rails
            ["Prefer Rails conventions over bespoke abstractions", "Verify N+1 queries", "Use Turbo/Stimulus"]
          when :pwa
            ["Mobile-first viewport", "Touch target 44px+", "Verify offline shell"]
          when :brgen
            ["Marketplace trust patterns", "City-specific location discovery"]
          else
            []
          end
        end
      end
    end
  end
end
