# frozen_string_literal: true

module Shared
  class ReviewCase < ApplicationRecord
    self.table_name = "shared_review_cases"
    belongs_to :reviewable, polymorphic: true
    enum :status, { open: 0, approved: 1, rejected: 2 }, default: :open
  end
end
