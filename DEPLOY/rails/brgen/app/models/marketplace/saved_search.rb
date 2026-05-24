# frozen_string_literal: true

class Marketplace::SavedSearch < ApplicationRecord
  belongs_to :user
  belongs_to :category, class_name: "Marketplace::Category", optional: true

  validates :name, length: { maximum: 120 }, allow_blank: true
  validates :query, length: { maximum: 200 }, allow_blank: true

  def title
    name.presence || query.presence || category&.name || "Saved search"
  end
end
