# frozen_string_literal: true

class Maintainer < ApplicationRecord
  self.table_name = "bsdports_maintainers"
  has_many :ports, dependent: :nullify
  validates :email, presence: true, uniqueness: true
end
