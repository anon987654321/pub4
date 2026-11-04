# frozen_string_literal: true

require "uri"

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
  has_many :security_advisory_ports, dependent: :destroy
  has_many :security_advisories, through: :security_advisory_ports

  validates :name, :version, :pkgpath, presence: true
  validates :pkgpath, uniqueness: { scope: :platform_id }
  validate :homepage_uses_safe_protocol

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
      nil
    end

    binds = {}
    predicates = terms.each_with_index.map do |term, index|
      key = :"term_#{index}"
      binds[key] = "%#{term}%"
      like = ->(column) { "#{column} LIKE :#{key}" }
      fields = %w[ports.pkgpath ports.version ports.description ports.maintainer].map(&like)
      fields.concat(%w[ports.name ports.comment].map(&like)) if ids.nil?
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
          JOIN security_advisory_ports ON security_advisory_ports.security_advisory_id = security_advisories.id
          WHERE security_advisory_ports.port_id = ports.id AND (#{advisory_fields.join(" OR ")})
        )
      SQL
      "(#{fields.join(' OR ')})"
    end

    related = where(predicates.join(" AND "), binds)
    ids&.any? ? related.or(where(id: ids)) : related
  }
  # A port named or pathed exactly as typed leads; "git" listed git-annex,
  # git-crypt and gitea before git itself.
  scope :exact_match_first, ->(q) {
    exact = sanitize_sql_array([ "CASE WHEN ports.name = :q OR ports.pkgpath = :q THEN 0 ELSE 1 END", { q: q.to_s } ])
    order(Arel.sql(exact))
  }
  # The order the index and its later pages share: newest first on request,
  # otherwise an exact match for the query and then by name.
  scope :ordered_for, ->(query, sort) {
    next order(last_updated: :desc) if sort == "updated"

    (query.present? ? exact_match_first(query) : all).order(:name)
  }
  # The whole list the infinite-scroll pages draw from.
  scope :listed, ->(query:, category_id:, sort:) {
    scope = query.present? ? search(query) : all
    scope = scope.by_category(category_id) if category_id.present?
    scope.ordered_for(query, sort)
  }
  scope :semantic_search, ->(q) { search(q) } # stub for sqlite-vec embeddings on description (DG02)

  # Comments, advisories and version history are rows that never touch the
  # port, so the port page's ETag carries each one's newest change. One query,
  # not four; the stored timestamps keep their microseconds.
  def self.related_freshness(id)
    where(id:).pick(
      per_port(Comment, :updated_at), per_port(Comment, :id, :count),
      newest_advisory, per_port(PortUpdate, :updated_at)
    )
  end

  # A correlated subquery: one aggregate over this port's rows in another table.
  def self.per_port(model, column, aggregate = :maximum)
    table = model.arel_table
    query = table.project(table[column].public_send(aggregate))
    Arel::Nodes::Grouping.new(query.where(table[:port_id].eq(arel_table[:id])))
  end

  def self.newest_advisory
    advisories = SecurityAdvisory.arel_table
    links = SecurityAdvisoryPort.arel_table
    query = advisories.project(advisories[:updated_at].maximum)
                      .join(links).on(links[:security_advisory_id].eq(advisories[:id]))
    Arel::Nodes::Grouping.new(query.where(links[:port_id].eq(arel_table[:id])))
  end
  private_class_method :per_port, :newest_advisory

  # "12-devel-py-foo": the id finds the row and the pkgpath makes the URL
  # readable. A pkgpath alone cannot be the param: it holds slashes, the same
  # pkgpath exists once per platform, and hyphens inside it (devel/py-foo)
  # meant the old "-" for "/" swap could never be decoded.
  def to_param
    "#{id}-#{pkgpath.to_s.parameterize}" if id
  end

  # The one lookup ports and their comments share: an exact pkgpath typed into
  # the URL first, then the leading id of to_param ("12-devel-git" casts to 12).
  def self.from_param(param)
    find_by(pkgpath: param.to_s) || find(param)
  end

  # The port as schema.org SoftwareApplication. url is the project's homepage
  # when the port names one, else the port's own page.
  def software_application_schema(page_url:)
    url = homepage.to_s.match?(%r{\Ahttps?://}i) ? homepage : page_url

    {
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",

      "name" => name,
      "softwareVersion" => version,
      "operatingSystem" => "OpenBSD",
      "applicationCategory" => category&.name,
      "description" => comment.presence,
      "url" => url,
    }.compact
  end

  def watched_by?(user)
    watches.exists?(user: user)
  end

  def homepage_uses_safe_protocol
    return if homepage.blank?

    uri = URI.parse(homepage)
    errors.add(:homepage, "must use HTTP or HTTPS") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:homepage, "is invalid")
  end

  def latest_update
    port_updates.order(committed_at: :desc).first
  end
end
