# frozen_string_literal: true

class Port < ApplicationRecord
  # Engine-ize Shared via pub4-shared
  include Shared::Reactable
  include Shared::Notifiable
  belongs_to :platform
  belongs_to :category
  belongs_to :maintainer, optional: true
  has_many :dependencies, dependent: :destroy
  has_many :depends_on, through: :dependencies, source: :depends_on
  has_many :dependents, class_name: "Dependency", foreign_key: :depends_on_id, dependent: :destroy,
           inverse_of: :depends_on
  has_many :reverse_deps, through: :dependents, source: :port
  has_many :port_updates, dependent: :destroy
  has_many :watches, dependent: :destroy
  has_many :watchers, through: :watches, source: :user
  has_many :comments, dependent: :destroy
  has_many :security_advisories, dependent: :destroy

  validates :name, :version, :pkgpath, presence: true
  validates :pkgpath, uniqueness: { scope: :platform_id }

  scope :recent_updates, -> { joins(:port_updates).order("port_updates.committed_at DESC").distinct }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :by_maintainer, ->(maintainer) { where(maintainer_id: maintainer.id) }
  scope :search, ->(q) {
    ids = connection.select_values(sanitize_sql_array([ "SELECT rowid FROM ports_fts WHERE ports_fts MATCH ?", q ]))
    ids.any? ? where(id: ids) : none
  }
  scope :semantic_search, ->(q) { search(q) } # stub for sqlite-vec embeddings on description (DG02)

  def watched_by?(user)
    watches.exists?(user: user)
  end

  def latest_update
    port_updates.order(committed_at: :desc).first
  end
end
