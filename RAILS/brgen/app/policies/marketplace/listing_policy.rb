# frozen_string_literal: true

module Marketplace
  class ListingPolicy < ::ApplicationPolicy
    def index?
      true
    end

    def show?
      return false unless seller_active?
      return true if owner?

      record.status != "removed" && !record.expired?
    end

    def create?
      # Craigslist-style: anyone can list without signup (soft guest ok).
      user.present?
    end

    def update?
      owner?
    end

    def destroy?
      owner?
    end

    def renew?
      owner?
    end

    class Scope < Scope
      # `live`, not `active`: a listing whose window has lapsed is still active
      # — that is what lets its owner see and renew it — but it does not belong
      # on a public index. Expiry is a scope rather than a state change for
      # exactly that reason.
      def resolve
        scope.live.joins(:user).where(users: { deleted_at: nil, deletion_scheduled_at: nil })
      end
    end

    private

    def seller_active?
      return false unless record.user_id

      User.where(
        id: record.user_id,
        deleted_at: nil,
        deletion_scheduled_at: nil
      ).exists?
    end
  end
end
