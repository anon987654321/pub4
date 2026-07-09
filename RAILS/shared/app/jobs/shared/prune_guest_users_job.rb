# frozen_string_literal: true

module Shared
  class PruneGuestUsersJob < ApplicationJob
    queue_as :default

    def perform
      ::User.where(guest: true)
            .where(created_at: ..7.days.ago)
            .where.missing(:sessions)
            .in_batches(of: 500, &:destroy_all)
    end
  end
end
