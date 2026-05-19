# frozen_string_literal: true

class MessageReceipt < ApplicationRecord
  belongs_to :message
  belongs_to :user
end
