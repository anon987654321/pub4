# frozen_string_literal: true

class Category < ApplicationRecord
  has_many :categorizations, dependent: :destroy
  has_many :posts, through: :categorizations

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  before_validation :generate_slug, on: :create

  def to_param = slug

  private

  def generate_slug
    self.slug ||= name.to_s.parameterize
  end
end
