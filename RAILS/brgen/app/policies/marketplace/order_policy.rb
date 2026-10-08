# frozen_string_literal: true

module Marketplace
  class OrderPolicy < Shared::RecordPolicy
    def show?
      participant?
    end

    def update?
      record.seller == user
    end

    private

    def participant?
      user.present? && (record.buyer == user || record.seller == user)
    end

    def owner?
      record.seller == user
    end
  end
end
