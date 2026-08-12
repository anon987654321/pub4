# frozen_string_literal: true

module Shared
  class RecordPolicy < ::ApplicationPolicy
    # `|| user.present?` was here and granted show to everyone. Guest users are
    # created for every anonymous visitor (Shared::Authentication#find_or_create_
    # guest_user), so `user` is present on essentially every request and the
    # clause made this method return true unconditionally.
    #
    # Not exploitable today: this is Pundit.policy_class, the default for a record
    # with no policy of its own, and nothing in the three apps calls `authorize` —
    # Pundit is used only for `policy_scope` in the marketplace listings
    # controller, and the per-record checks are hand-rolled before_actions
    # (authorize_owner, require_real_user, amber's authorize!). So this was a hole
    # waiting for its first caller rather than an open one, which is the only
    # reason it is a two-line change and not an incident.
    def show?
      public_record? || owner?
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

    # Fail closed. This rescued StandardError and returned true, so any error
    # reading `public?` — a missing column, a nil, a raise inside an override —
    # answered "yes, this record is public". A guard that grants access when it
    # cannot decide is not a guard. Same shape as PostModeration#approve?, which
    # rescued its way into approving 57 spam posts.
    def public_record?
      record.respond_to?(:public?) && record.public?
    rescue StandardError => e
      Rails.logger.warn("RecordPolicy#public_record? #{e.class}: #{e.message}")
      false
    end
  end
end
