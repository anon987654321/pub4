# frozen_string_literal: true
# AN406/AN1702: Turbo morph refresh

module Shared
  module TurboMorphing
    extend ActiveSupport::Concern

    included do
      turbo_refreshes_with :morph, scroll: :preserve if respond_to?(:turbo_refreshes_with)
    end
  end
end