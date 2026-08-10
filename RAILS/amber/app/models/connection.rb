# frozen_string_literal: true

class Connection < ApplicationRecord
  STATUSES = %w[pending accepted blocked].freeze

  belongs_to :requester, class_name: "User"
  belongs_to :addressee, class_name: "User"

  validates :status, inclusion: { in: STATUSES }
  validates :requester_id, uniqueness: { scope: :addressee_id }
  validate :no_self_connection

  scope :accepted, -> { where(status: "accepted") }
  scope :pending, -> { where(status: "pending") }

  def accept! = update!(status: "accepted")
  def block! = update!(status: "blocked")

  private

  def no_self_connection
    errors.add(:addressee, :self_connection) if requester_id == addressee_id
  end
end
