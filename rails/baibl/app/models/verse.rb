# frozen_string_literal: true

class Verse < ApplicationRecord
  self.table_name = "baibl_verses"
  belongs_to :chapter
  validates :number, :text, presence: true
end
