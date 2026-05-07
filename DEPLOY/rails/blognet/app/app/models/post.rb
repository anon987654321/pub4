class Post < ApplicationRecord
  belongs_to :blog
  belongs_to :user
  has_rich_text :body
  has_many_attached :images
  has_many :comments, dependent: :destroy
  has_many :categorizations, dependent: :destroy
  has_many :categories, through: :categorizations
  has_many :taggings, dependent: :destroy
  has_many :tags, through: :taggings

  validates :title, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  before_validation :generate_slug, on: :create
  before_save :set_published_at

  scope :published, -> { where(published: true).order(published_at: :desc) }
  scope :drafts,    -> { where(published: false) }
  scope :recent,    -> { order(created_at: :desc) }

  def to_param = slug

  def reading_time
    words = body.to_plain_text.split.size
    [(words / 200.0).ceil, 1].max
  end

  private

  def generate_slug
    self.slug ||= title.to_s.parameterize
  end

  def set_published_at
    self.published_at = Time.current if published? && published_at.nil?
  end
end
