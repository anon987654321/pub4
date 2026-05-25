# frozen_string_literal: true

module Shared
  module SocialSubstrate
    extend ActiveSupport::Concern

    included do
      has_many :reactions, as: :reactable, class_name: "Shared::Reaction", dependent: :destroy
      has_many :received_follows, as: :followable, class_name: "Shared::Follow", dependent: :destroy
    end
  end
end
