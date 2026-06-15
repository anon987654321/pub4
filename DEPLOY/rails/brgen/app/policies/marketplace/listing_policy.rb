# frozen_string_literal: true

module Marketplace
  class ListingPolicy < ApplicationPolicy
    def index?
      true
    end

    def show?
      record.status != "removed" || owner?
    end

    def create?
      user.present? && !user.guest?
    end

    def update?
      owner?
    end

    def destroy?
      owner?
    end

    class Scope < Scope
      def resolve
        scope.active
      end
    end
  end
end