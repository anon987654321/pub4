# frozen_string_literal: true

module Shared
  module ApplicationSetup
    extend ActiveSupport::Concern

    included do
      include Shared::RescueHandlers
      include Shared::Authentication
      include Shared::PunditAuthorization
      include Shared::PagyPagination
      include Shared::VisitCounting
      # Rails' automatic helper inclusion (config.action_controller.include_all_helpers)
      # scans the HOST app's app/helpers/, but pub4-shared is mounted as a separate
      # engine gem -- its helpers are not in that scan path and need an explicit
      # `helper` call. Other shared helpers (Shared::SearchHelper's
      # live_search_index, say) happen to be reachable through a different
      # inclusion path; Shared::StimulusFormHelper is not, and without this line
      # password_visibility_field raises on every sessions/new render.
      helper Shared::StimulusFormHelper
      helper Shared::AffiliateHelper
      allow_browser versions: :modern
      turbo_refreshes_with :morph, scroll: :preserve
      stale_when_importmap_changes
    end
  end
end
