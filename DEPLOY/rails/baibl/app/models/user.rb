# frozen_string_literal: true

class User < ApplicationRecord
  include Shared::UserAuthExtensions
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :highlights, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :reading_plans, dependent: :destroy
  has_many :annotations, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
