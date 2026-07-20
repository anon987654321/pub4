# frozen_string_literal: true

module Shared
  class AnonymousPostQuota < ApplicationRecord
    self.table_name = "anonymous_post_quotas"

    LIMIT = 2

    validates :fingerprint, presence: true, uniqueness: true
    validates :post_count, numericality: { greater_than_or_equal_to: 0 }
  end
end
