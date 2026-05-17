class PackingListItem < ApplicationRecord
  belongs_to :packing_list
  belongs_to :item

  validates :item_id, uniqueness: { scope: :packing_list_id }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
