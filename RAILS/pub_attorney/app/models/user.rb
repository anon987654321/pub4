# frozen_string_literal: true

class User < ApplicationRecord
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  include Shared.concern(:GeoLocatable) rescue nil
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :cases, dependent: :destroy
  has_one :lawyer, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end