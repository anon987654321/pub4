# frozen_string_literal: true

class User < ApplicationRecord
  include Shared::UserAuthExtensions
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :resources, dependent: :nullify
  has_many :posts, dependent: :nullify
  has_many :comments, dependent: :nullify
  has_many :food_listings, dependent: :nullify
  has_many :food_requests, dependent: :destroy
  has_many :support_requests, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
