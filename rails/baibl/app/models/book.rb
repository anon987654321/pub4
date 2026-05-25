# frozen_string_literal: true

class Book < ApplicationRecord
  self.table_name = "baibl_books"
  has_many :chapters, -> { order(:number) }, dependent: :destroy
  validates :name, :testament, presence: true
end
