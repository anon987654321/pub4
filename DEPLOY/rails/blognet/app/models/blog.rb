# frozen_string_literal: true

class Blog < ApplicationRecord
  belongs_to :user
  has_many :posts, dependent: :destroy
  has_one_attached :banner

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  before_validation :generate_slug, on: :create

  scope :published, -> { where(published: true) }
  scope :recent,    -> { order(created_at: :desc) }

  def to_param = slug

  private

  def generate_slug
    self.slug ||= name.to_s.parameterize
  end
end
