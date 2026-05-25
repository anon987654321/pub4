# frozen_string_literal: true

module Brgen
  module Moderatable
    extend ActiveSupport::Concern

    included do
      has_many :review_cases, as: :reviewable, class_name: "Shared::ReviewCase", dependent: :destroy
      after_create_commit :enqueue_moderation_review
    end

    def enqueue_moderation_review
      Shared::ReviewCase.create!(reviewable: self)
    end
  end
end
