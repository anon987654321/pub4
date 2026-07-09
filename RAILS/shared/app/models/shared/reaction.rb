# frozen_string_literal: true

module Shared
  class Reaction < ApplicationRecord
    self.table_name = "reactions"

    KINDS = %w[like love laugh wow sad angry local].freeze

    belongs_to :user
    belongs_to :reactable, polymorphic: true

    validates :kind, inclusion: { in: KINDS }
    validates :user_id, uniqueness: { scope: %i[reactable_type reactable_id kind] }

    after_create_commit { broadcast_replace_later_to stream_name }
    after_destroy_commit { broadcast_replace_later_to stream_name }

    private

    def stream_name
      "shared:reactions:#{reactable_type}:#{reactable_id}"
    end
  end
end
