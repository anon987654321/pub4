# frozen_string_literal: true

module Shared
  # Lets `dependent: :destroy` associations load, despite strict_loading_by_default.
  #
  # A destroy cascade must read its dependents to delete them, and no amount of
  # `includes` at the query site avoids that — so strict loading on such an
  # association can never catch an N+1 worth catching. It can only crash, and it
  # crashed on the commonest path there is: every controller `destroy` action
  # finds its record by id with nothing preloaded.
  #
  # Measured on 2026-07-28: 121 cascading associations across amber, brgen and
  # bsdports, all of them strict-loading. brgen alone had 76, including
  # User#sessions, User#posts and User#notifications — so deleting an account
  # raised rather than deleting it.
  #
  # Done here rather than as 121 hand-written `strict_loading: false` options so
  # a new cascading association is safe by default. An explicit
  # `strict_loading: true` still wins; nothing else about strict loading changes,
  # and the reads that strict loading exists to catch stay caught.
  module CascadingAssociationsLoad
    extend ActiveSupport::Concern

    # :nullify belongs here for the same reason as the rest. A has_one nullify
    # loads its dependent to clear the foreign key, so `Tv::Video#originated_sound`
    # — a sound that outlives the clip it came from — raised
    # StrictLoadingViolationError on destroy, which is the crash this concern
    # exists to stop and not an N+1 anyone could have preloaded away.
    CASCADES = %i[destroy destroy_async delete_all nullify].freeze

    class_methods do
      def has_many(name, scope = nil, **options, &extension)
        super(name, scope, **cascade_safe(options), &extension)
      end

      def has_one(name, scope = nil, **options)
        super(name, scope, **cascade_safe(options))
      end

      private

      def cascade_safe(options)
        return options unless CASCADES.include?(options[:dependent])
        return options if options.key?(:strict_loading)

        options.merge(strict_loading: false)
      end
    end
  end
end
