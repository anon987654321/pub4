# frozen_string_literal: true

module Maps
  class BaseController < ApplicationController
    helper_method :place_kind_label

    private

    # Place#kind is free text entered per place, so a kind with no translation
    # still reads as its own humanized value rather than translation_missing.
    def place_kind_label(kind)
      return "" if kind.blank?

      I18n.t(kind, scope: "maps.kinds", default: kind.to_s.humanize)
    end
  end
end
