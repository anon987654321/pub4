# frozen_string_literal: true

module Maps
  class BaseController < ApplicationController
    helper_method :place_kind_label

    private

    # Place is deliberately not acts_as_tenant scoped, because shops and
    # restaurants consume it too. Every Maps read must therefore name the city
    # explicitly; a missing city resolves to an empty scope, never the whole table.
    def places_in_current_city
      city = Current.city_record
      return Place.none unless city

      Place.where(city_id: city.id)
    end

    # Place#kind is free text entered per place, so a kind with no translation
    # still reads as its own humanized value rather than translation_missing.
    def place_kind_label(kind)
      return "" if kind.blank?

      I18n.t(kind, scope: "maps.kinds", default: kind.to_s.humanize)
    end
  end
end
