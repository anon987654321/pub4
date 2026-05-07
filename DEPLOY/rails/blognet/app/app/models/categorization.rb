class Categorization < ApplicationRecord
  belongs_to :post
  belongs_to :category

  validates :post_id, uniqueness: { scope: :category_id }
end
