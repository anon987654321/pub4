# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :watches, dependent: :destroy
  has_many :watched_ports, through: :watches, source: :port
  has_many :comments, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
