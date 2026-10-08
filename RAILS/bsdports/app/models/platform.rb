# frozen_string_literal: true

class Platform < ApplicationRecord
  has_many :categories, dependent: :destroy
  has_many :ports, dependent: :destroy
  has_many :import_runs, dependent: :destroy

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+\z/ }

  scope :active, -> { where(active: true) }

  def self.openbsd = find_by!(slug: "openbsd")
  def self.freebsd = find_by!(slug: "freebsd")
  def self.netbsd = find_by!(slug: "netbsd")
end
