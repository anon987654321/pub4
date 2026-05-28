# frozen_string_literal: true

class Port < ApplicationRecord
  belongs_to :category
  has_many :dependencies, dependent: :destroy
  has_many :depends_on, through: :dependencies, source: :depends_on
  has_many :dependents, class_name: "Dependency", foreign_key: :depends_on_id
  has_many :reverse_deps, through: :dependents, source: :port
  has_many :port_updates, dependent: :destroy
  has_many :watches, dependent: :destroy
  has_many :watchers, through: :watches, source: :user
  has_many :comments, dependent: :destroy

  validates :name, :version, :pkgpath, presence: true
  validates :pkgpath, uniqueness: true

  scope :recent_updates, -> { joins(:port_updates).order("port_updates.committed_at DESC").distinct }
  scope :by_category,    ->(cat) { where(category: cat) }
  scope :search, ->(q) {
    ids = connection.select_values(sanitize_sql_array(["SELECT rowid FROM ports_fts WHERE ports_fts MATCH ?", q]))
    ids.any? ? where(id: ids) : none
  }

  def watched_by?(user)
    watches.exists?(user: user)
  end

  def latest_update
    port_updates.order(committed_at: :desc).first
  end
end
