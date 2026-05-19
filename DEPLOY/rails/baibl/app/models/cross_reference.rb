# frozen_string_literal: true

class CrossReference < ApplicationRecord
  belongs_to :verse
  belongs_to :target_verse, class_name: "Verse"

  KINDS = %w[lexical thematic parallel typological fulfillment].freeze
  validates :kind, inclusion: { in: KINDS }, allow_nil: true
  validates :verse_id, uniqueness: { scope: :target_verse_id }
end
