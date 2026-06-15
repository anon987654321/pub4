# frozen_string_literal: true

class PortUpdate < ApplicationRecord
  # Engine-ize Shared
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  belongs_to :port

  validates :new_version, presence: true

  scope :recent, -> { order(committed_at: :desc) }
end
