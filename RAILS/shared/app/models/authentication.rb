# frozen_string_literal: true

module Shared
  class Authentication < ::ApplicationRecord
    self.table_name = "authentications"

    belongs_to :user

    validates :provider, presence: true
    validates :uid, presence: true, uniqueness: { scope: :provider }
  end
end
