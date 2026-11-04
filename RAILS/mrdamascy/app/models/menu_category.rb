# frozen_string_literal: true

class MenuCategory < ApplicationRecord
  include LocalizedColumns

  belongs_to :kitchen
  has_many :menu_items, dependent: :destroy
  # The menu only sells what the kitchen can make today — the catalog loads
  # this association (with options) so views present instead of query.
  has_many :available_items, -> { available }, class_name: "MenuItem"

  validates :name, :slug, presence: true

  scope :ordered, -> { order(:position, :id) }
end
