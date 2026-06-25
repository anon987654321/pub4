# frozen_string_literal: true

class Video < ApplicationRecord
  belongs_to :user
  has_many :comments, dependent: :destroy
  has_one_attached :file

  validates :title, presence: true
end