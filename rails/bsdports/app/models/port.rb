# frozen_string_literal: true

class Port < ApplicationRecord
  self.table_name = "bsdports_ports"
  has_many :dependencies, dependent: :destroy
  has_many :security_advisories, dependent: :destroy
  belongs_to :maintainer, optional: true
  validates :pkgname, presence: true, uniqueness: true
end
