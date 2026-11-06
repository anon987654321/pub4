# frozen_string_literal: true

# A minimal receipt for a copy review. Submitted wording and product data are
# never stored; the receipt keeps only digests, the verdict summary and finding
# codes so a later audit can identify exactly which inputs and reviewer ran.
class ApiCopyReview < ApplicationRecord
  self.table_name = "api_copy_reviews"

  belongs_to :api_key

  STATUSES = %w[pass fail inconclusive].freeze

  validates :request_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :creative_sha256, :reviewer_sha256, presence: true
  validates :product_sha256, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validates :creative_sha256, :reviewer_sha256,
            format: { with: /\A[0-9a-f]{64}\z/ }
  validates :source_trust, inclusion: { in: %w[caller_supplied_unverified] }
end
