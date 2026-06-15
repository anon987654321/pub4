# frozen_string_literal: true

class Chapter < ApplicationRecord
  # Engine-ize Shared
  include Shared.concern(:Reactable) rescue nil
  include Shared.concern(:Notifiable) rescue nil
  belongs_to :book
  has_many :verses, dependent: :destroy

  validates :number, presence: true
  validates :number, uniqueness: { scope: :book_id }

  scope :ordered, -> { order(:number) }

  def reference = "#{book.name} #{number}"
end
