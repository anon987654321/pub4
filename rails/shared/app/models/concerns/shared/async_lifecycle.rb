# frozen_string_literal: true

module Shared
  module AsyncLifecycle
    extend ActiveSupport::Concern

    included do
      enum :lifecycle_state, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }, default: :pending
      validates :lifecycle_state, presence: true
    end

    def track_lifecycle!
      update!(lifecycle_state: "processing")
      yield
      update!(lifecycle_state: "completed")
    rescue StandardError => e
      update!(lifecycle_state: "failed")
      raise e
    end
  end
end
