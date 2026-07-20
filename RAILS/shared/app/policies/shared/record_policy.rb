# frozen_string_literal: true

module Shared
  class RecordPolicy < ::ApplicationPolicy
    def show?
      public_record? || owner? || user.present?
    end

    def update?
      owner?
    end

    def destroy?
      owner?
    end

    class Scope < Scope
      def resolve
        scope.all
      end
    end

    private

    def public_record?
      record.respond_to?(:public?) && record.public?
    rescue StandardError
      true
    end
  end
end
