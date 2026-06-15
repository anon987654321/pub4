# frozen_string_literal: true

class User < ApplicationRecord
  # Engine-ize Shared
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  include Shared.concern(:GeoLocatable) rescue nil
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :watches, dependent: :destroy
  has_many :watched_ports, through: :watches, source: :port
  has_many :comments, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
