# frozen_string_literal: true

class Case < ApplicationRecord
  belongs_to :user
  belongs_to :lawyer, optional: true
  has_many :documents, dependent: :destroy

  validates :title, presence: true
end