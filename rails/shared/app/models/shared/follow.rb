# frozen_string_literal: true

module Shared
  class Follow < ApplicationRecord
    self.table_name = "shared_follows"
    belongs_to :user
    belongs_to :followable, polymorphic: true
    validates :user_id, uniqueness: { scope: [:followable_type, :followable_id] }
  end
end
