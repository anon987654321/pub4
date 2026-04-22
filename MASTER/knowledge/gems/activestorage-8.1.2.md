# frozen_string_literal: true

class Message < ApplicationRecord
  # Attach any number of photos and documents to a message.
  has_many_attached :photos
  has_many_attached :documents

  # ------------------------------------------------------------------
  # Validations
  # ------------------------------------------------------------------
  validates :photos,
            content_type: %w[image/png image/jpg image/jpeg],
            size: { less_than: 5.megabytes, message: 'is too large (max 5 MB)' },
            limit: { max: 10, message: 'exceeds the limit of 10 photos' },
            if: -> { photos.attached? }

  validates :documents,
            content_type: [
              'application/pdf',
              'application/msword',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            ],
            size: { less_than: 10.megabytes, message: 'is too large (max 10 MB)' },
            limit: { max: 5, message: 'exceeds the limit of 5 documents' },
            if: -> { documents.attached? }

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------
  # Returns true if the message has any attached files.
  def attached?
    photos.attached? || documents.attached?
  end

  # Purge all attachments – useful for cleanup tasks.
  def purge_all_attachments!
    photos.purge_later
    documents.purge_later
  end
end