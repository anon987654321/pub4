# frozen_string_literal: true

class Place < ApplicationRecord
  belongs_to :city
  belongs_to :neighborhood, optional: true

  validates :kind, presence: true
  validates :latitude, presence: true
  validates :longitude, presence: true
  validates :name, presence: true

  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM places_fts WHERE places_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }
end
