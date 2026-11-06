# frozen_string_literal: true

module Fediverse
  # Fan one activity out to every inbox that should receive it.
  #
  # Takes a built payload rather than a record id, for two reasons: a Delete is
  # sent for a row that no longer exists to reload, and serialising once here
  # beats serialising identically inside every per-inbox job.
  #
  # Split from DeliveryJob so one unreachable instance retries alone instead of
  # holding up — or repeating — delivery to everyone else, which is what a
  # single job looping over followers would do.
  class DistributeJob < ApplicationJob
    queue_as :bulk

    def perform(user_id:, payload:)
      user = User.find_by(id: user_id)
      return if user.nil? || !user.federated?

      user.followers_inboxes.each do |inbox|
        DeliveryJob.perform_later(inbox_url: inbox, user_id: user.id, payload: payload)
      end
    end
  end
end
