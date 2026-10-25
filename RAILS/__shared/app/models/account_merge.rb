# frozen_string_literal: true

# Records the transfer of a persisted anonymous identity into a registered
# account. The guest row remains as an audit referent; content and messages
# move to the destination inside the same database transaction.
class AccountMerge < ApplicationRecord
  belongs_to :guest_user, class_name: "User"
  belongs_to :user

  validates :status, presence: true
  validates :guest_user_id, uniqueness: { scope: :user_id }
end
