# frozen_string_literal: true

class ConsentEvent < ApplicationRecord
  belongs_to :user

  validates :purpose, :decision, presence: true

  enum :decision, { granted: "granted", revoked: "revoked" }
end
