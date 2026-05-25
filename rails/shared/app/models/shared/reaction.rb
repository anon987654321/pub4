# frozen_string_literal: true

module Shared
  class Reaction < ApplicationRecord
    self.table_name = "shared_reactions"
    belongs_to :user
    belongs_to :reactable, polymorphic: true
    validates :user_id, uniqueness: { scope: [:reactable_type, :reactable_id] }
  end
end
