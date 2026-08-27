# frozen_string_literal: true

class ExpiredMessagesSweepJob < ApplicationJob
  queue_as :bulk

  def perform
    Message.where(expires_at: ..Time.current).find_each(&:expire!)

    # Typing rows that were never sent. Message#after_create deletes the sender's
    # indicator, so the ones left behind belong to people who started a reply and
    # closed the tab. The `active` scope already hides them, so nothing is wrong
    # on screen — but the highest-frequency write in the app was the only one
    # with no floor on the table it writes to.
    TypingIndicator.where(expires_at: ..1.hour.ago).delete_all
  end
end
