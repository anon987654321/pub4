# frozen_string_literal: true

class DeviceLogin < ApplicationRecord
  belongs_to :user

  def new_device?
    created_at > 1.minute.ago
  end
end