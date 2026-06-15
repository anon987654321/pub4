# frozen_string_literal: true

class City < ApplicationRecord
  has_many :neighborhoods, dependent: :destroy
  has_many :places, dependent: :destroy
  has_many :users, dependent: :nullify
  has_many :posts, dependent: :nullify

  # ActsAsTenant + domain resolution means city is chosen automatically from the request's TLD/domain.
  # No user-facing city switcher; each city domain (brgen.no, lsangeles.com, oshlo.no, ...) is isolated.

  validates :country_code, presence: true
  validates :domain, presence: true, uniqueness: true
  validates :locale, presence: true
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
