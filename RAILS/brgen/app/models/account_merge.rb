# frozen_string_literal: true

class AccountMerge < ApplicationRecord
  belongs_to :guest_user, class_name: "User"
  belongs_to :user

  validates :status, presence: true
end
