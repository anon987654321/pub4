# frozen_string_literal: true

module Shared
  module ApplicationSetup
    extend ActiveSupport::Concern

    included do
      include Shared::RescueHandlers
      include Authentication
      include Shared::PunditAuthorization
      include Shared::PagyPagination
      include Shared::VisitCounting
      # Rails' automatic helper inclusion only scans the host app's app/helpers/,
      # not pub4-shared's (a separate engine gem) -- see brgen's
      # ApplicationController for the same fix and the full explanation.
      helper Shared::StimulusFormHelper
      helper Shared::AffiliateHelper
      allow_browser versions: :modern
      turbo_refreshes_with :morph, scroll: :preserve
      stale_when_importmap_changes
    end
  end
end
