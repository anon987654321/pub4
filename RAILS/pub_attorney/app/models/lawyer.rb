# frozen_string_literal: true

class Lawyer < ApplicationRecord
  belongs_to :user, optional: true
  has_many :cases, dependent: :nullify

  validates :name, presence: true
end