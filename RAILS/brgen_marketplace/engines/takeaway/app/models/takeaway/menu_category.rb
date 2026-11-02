# frozen_string_literal: true

class Takeaway::MenuCategory < ApplicationRecord
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  has_many :menu_items, class_name: "Takeaway::MenuItem", dependent: :nullify

  before_validation { self.name = name.to_s.strip.presence }

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: :restaurant_id, case_sensitive: false }
end
