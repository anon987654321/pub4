class Restaurant < ApplicationRecord
  has_many :menu_items, dependent: :destroy
  has_many :orders,     dependent: :nullify
  validates :name, :address, presence: true
  geocoded_by :address, after_validation :geocode, if: :will_save_change_to_address?
end

class MenuItem < ApplicationRecord
  belongs_to :restaurant  enum availability: { available: 0, sold_out: 1 }
  monetize :price_cents
end

class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user
  enum status: { placed: 0, accepted: 1, preparing: 2, dispatched: 3, delivered: 4, canceled: 5 }
end
