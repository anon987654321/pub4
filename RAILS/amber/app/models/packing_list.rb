# frozen_string_literal: true

class PackingList < ApplicationRecord
  belongs_to :user
  has_many :packing_list_items, dependent: :destroy
  has_many :items, through: :packing_list_items

  validates :name, :starts_on, :ends_on, presence: true
  validate :ends_after_start

  def duration_days
    return 0 unless starts_on && ends_on
    (ends_on - starts_on).to_i + 1
  end

  private

  def ends_after_start
    return unless starts_on && ends_on
    errors.add(:ends_on, :before_start) if ends_on < starts_on
  end
end
