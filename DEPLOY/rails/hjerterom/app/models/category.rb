# frozen_string_literal: true

class Category < ApplicationRecord
  has_many :resources, dependent: :nullify
  has_many :posts, dependent: :nullify

  TYPES = %w[mental_health food housing legal community other].freeze

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
  validates :type_of, inclusion: { in: TYPES }, allow_nil: true

  scope :of_type, ->(t) { where(type_of: t) }
end
