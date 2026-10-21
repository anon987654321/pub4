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
    terms = q.to_s.scan(/[[:alnum:]]+/).uniq
    next none if terms.empty?

    # Prefix matching keeps live search useful before a word is complete. FTS
    # covers name/comment; correlated lookups cover the other advertised fields.
    query = terms.map { |term| %("#{term.gsub('"', '""')}"*) }.join(" AND ")
    ids = begin
      connection.select_values(sanitize_sql_array([ "SELECT rowid FROM ports_fts WHERE ports_fts MATCH ?", query ]))
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.warn("bsdports search index unavailable: #{e.message}")
      []
    end

    binds = {}
    predicates = terms.each_with_index.map do |term, index|
      key = :"term_#{index}"
      binds[key] = "%#{term}%"
      like = ->(column) { "#{column} LIKE :#{key}" }
      fields = %w[ports.pkgpath ports.version ports.description ports.maintainer].map(&like)
      category_fields = %w[name slug description].map { |column| like.call("categories.#{column}") }
      fields << "EXISTS (SELECT 1 FROM categories WHERE categories.id = ports.category_id AND (#{category_fields.join(" OR ")}))"
      fields << "EXISTS (SELECT 1 FROM maintainers WHERE maintainers.id = ports.maintainer_id AND #{like.call('maintainers.name')})"
      dependency_fields = %w[name pkgpath comment description].map { |column| like.call("dependency_ports.#{column}") }
      fields << <<~SQL.squish
        EXISTS (
          SELECT 1 FROM dependencies
          JOIN ports AS dependency_ports ON dependency_ports.id = dependencies.depends_on_id
          WHERE dependencies.port_id = ports.id AND (#{dependency_fields.join(" OR ")})
        )
      SQL
      advisory_fields = %w[identifier title description].map { |column| like.call("security_advisories.#{column}") }
      fields << <<~SQL.squish
        EXISTS (
          SELECT 1 FROM security_advisories
          WHERE security_advisories.port_id = ports.id AND (#{advisory_fields.join(" OR ")})
        )
      SQL
      "(#{fields.join(' OR ')})"
    end

    related = where(predicates.join(" AND "), binds)
    ids.any? ? related.or(where(id: ids)) : related
  }
  scope :semantic_search, ->(q) { search(q) } # stub for sqlite-vec embeddings on description (DG02)

  def watched_by?(user)
    watches.exists?(user: user)
  end

  def latest_update
    port_updates.order(committed_at: :desc).first
  end
end
