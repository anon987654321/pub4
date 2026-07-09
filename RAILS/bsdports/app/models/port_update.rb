# frozen_string_literal: true

class PortUpdate < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  belongs_to :port

  validates :new_version, presence: true

  scope :recent, -> { order(committed_at: :desc) }
end
