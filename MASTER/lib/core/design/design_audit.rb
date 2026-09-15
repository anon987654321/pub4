# frozen_string_literal: true

module Master
  module Core
    module Design
      # The DesignAudit performs a systemic sweep of the UI to find
      # typographic and iconic inconsistencies.
      class DesignAudit
        def initialize(container)
          @container = container
        end

        # Audits a rendered surface for design debt.
        def audit(surface_data)
          {
            typography: audit_typography(surface_data),
            iconography: audit_iconography(surface_data),
            optical: audit_optical_alignment(surface_data)
          }
        end

        private

        def audit_typography(data)
          # Scans for arbitrary font-sizes not mapped to TypographyRoles
          arbitrary_sizes = data[:font_sizes].select { |s| !LayoutGrammar.validate(:type, s) }
          {
            arbitrary_count: arbitrary_sizes.size,
            violations: arbitrary_sizes,
            role_coverage: data[:roles].size / 11.0
          }
        end

        def audit_iconography(data)
          # Scans for inconsistent icon weights or sizes
          inconsistent_sizes = data[:icon_sizes].select { |s| !IconSystem.valid_size?(s) }
          {
            arbitrary_sizes: inconsistent_sizes,
            count: inconsistent_sizes.size
          }
        end

        def audit_optical_alignment(data)
          # Measures geometric vs optical center
          drift = data[:optical_drift] || 0
          {
            drift: drift,
            status: drift > 2 ? :off_center : :aligned
          }
        end
      end
    end
  end
end
