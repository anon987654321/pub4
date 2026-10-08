# frozen_string_literal: true

module Shared
  module ActorIdentity
    extend ActiveSupport::Concern

    private

    def shared_actor
      return current_or_guest_user if respond_to?(:current_or_guest_user, true)
      current_user if respond_to?(:current_user, true)
    end
  end
end
