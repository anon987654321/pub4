# frozen_string_literal: true

# vector is a JSON column, not pgvector, so amber stays on SQLite with the
# other two apps on one 1 GB box. pgvector is a Postgres extension; moving to it
# means a Postgres database, a pgvector column in place of the JSON one, and a
# real embedding backend behind WardrobeAi#embedding_for (apps.yml stack_later).
class GarmentEmbedding < ApplicationRecord
  belongs_to :item

  validates :provider, :model, presence: true
  validates :dimensions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
