# frozen_string_literal: true

class Chapter < ApplicationRecord
  self.table_name = "baibl_chapters"
  belongs_to :book
  has_many :verses, -> { order(:number) }, dependent: :destroy
end
