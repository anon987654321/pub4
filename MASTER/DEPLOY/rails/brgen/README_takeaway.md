Restaurant
  - has_many :menu_items, dependent: :destroy
  - has_many :orders, dependent: :nullify

MenuItem
  - belongs_to :restaurant

Order
  - belongs_to :restaurant
  - belongs_to :user