# frozen_string_literal: true

class AddLastRequestAtToNvdRateLimits < ActiveRecord::Migration[8.1]
  def change
    add_column :nvd_rate_limits, :last_request_at, :datetime
  end
end
