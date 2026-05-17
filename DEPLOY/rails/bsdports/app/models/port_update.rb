class PortUpdate < ApplicationRecord
  belongs_to :port

  validates :new_version, presence: true

  scope :recent, -> { order(committed_at: :desc) }
end
