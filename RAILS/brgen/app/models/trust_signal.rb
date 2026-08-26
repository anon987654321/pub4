# frozen_string_literal: true

class TrustSignal < ApplicationRecord
  belongs_to :user

  validates :kind, presence: true
  # TrustScore sums these rows, so a duplicate is a duplicate penalty or a
  # duplicate credit. The unique index in 20260825120000 is the real guard;
  # this validation also covers the case the index cannot, because SQLite
  # treats NULLs as distinct and `source` is nullable.
  validates :kind, uniqueness: { scope: %i[user_id source] }
end
