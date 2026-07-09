# frozen_string_literal: true

class Document < ApplicationRecord
  belongs_to :case
  has_one_attached :file

  validates :title, presence: true
end