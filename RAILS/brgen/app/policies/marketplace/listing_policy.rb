# frozen_string_literal: true

module Marketplace
  class ListingPolicy < ::ApplicationPolicy
    def index?
      true
    end

    def show?
      record.status != "removed" || owner?
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

    class Scope < Scope
      # `live`, not `active`: a listing whose window has lapsed is still active
      # — that is what lets its owner see and renew it — but it does not belong
      # on a public index. Expiry is a scope rather than a state change for
      # exactly that reason.
      def resolve
        scope.live
      end
    end
  end
end
