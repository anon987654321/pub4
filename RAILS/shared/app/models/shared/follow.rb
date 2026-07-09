# frozen_string_literal: true

module Shared
  class Follow < ApplicationRecord
    self.table_name = "follows"

    belongs_to :follower, class_name: "User"
    belongs_to :followable, polymorphic: true

    validates :follower_id, uniqueness: { scope: %i[followable_type followable_id] }
    validate :not_self

    after_create_commit { broadcast_replace_later_to stream_name }
    after_destroy_commit { broadcast_replace_later_to stream_name }

    private

    def not_self
      errors.add(:base, "cannot follow self") if followable == follower
    end

    def stream_name
      "shared:follows:#{followable_type}:#{followable_id}"
    end
  end
end
