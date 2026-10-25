# frozen_string_literal: true

# Private share drafts and their uploaded media are temporary. Destroy the rows
# through Active Record so Active Storage can purge the staged attachments.
class ShareDraftCleanupJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: "share-draft-cleanup", duration: 15.minutes, on_conflict: :discard

  def perform
    ShareDraft.expired.find_each(&:destroy)
  end
end
