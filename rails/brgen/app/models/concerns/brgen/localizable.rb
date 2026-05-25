# frozen_string_literal: true

module Brgen
  module Localizable
    extend ActiveSupport::Concern

    included do
      scope :in_current_locality, -> {
        where(city_slug: Thread.current[:brgen_city_context])
      }
    end
  end
end
