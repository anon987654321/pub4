# frozen_string_literal: true

class MessageReceipt < ApplicationRecord
  belongs_to :message
  belongs_to :user

  scope :read, -> { where.not(read_at: nil) }

  def read? = read_at.present?
  def delivered? = delivered_at.present?
end
