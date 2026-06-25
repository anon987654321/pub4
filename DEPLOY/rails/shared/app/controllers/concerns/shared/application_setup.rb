# frozen_string_literal: true

module Shared
  module ApplicationSetup
    extend ActiveSupport::Concern

    included do
      include Authentication
      include Shared::PunditAuthorization
      include Shared::PagyPagination
      allow_browser versions: :modern
      turbo_refreshes_with :morph, scroll: :preserve
      stale_when_importmap_changes
    end
  end
end