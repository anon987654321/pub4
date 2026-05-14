# frozen_string_literal: true

class City < ApplicationRecord
  has_many :neighborhoods, dependent: :destroy
  has_many :places, dependent: :destroy

  validates :country_code, presence: true
  validates :domain, presence: true, uniqueness: true
  validates :locale, presence: true
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
