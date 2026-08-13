# frozen_string_literal: true

# Stories delete themselves.
#
# `alive` already hides an expired story from every surface, so this is about
# the bytes rather than the visibility: without it, expired rows and their
# Active Storage blobs accumulate forever on a 1 GB VPS. destroy, not
# delete_all, precisely so the attachments and their variants go too.
class ExpiredStoriesSweepJob < ApplicationJob
  queue_as :bulk

  def perform
    Story.where(expires_at: ..Time.current).find_each(&:destroy)
  end
end
