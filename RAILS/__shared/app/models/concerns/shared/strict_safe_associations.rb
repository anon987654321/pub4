# frozen_string_literal: true

module Shared
  # Reads a belongs_to without tripping strict loading.
  #
  # ApplicationRecord sets strict_loading_by_default = true for every
  # environment. Only development downgrades a violation to a log line
  # (development.rb sets action_on_strict_loading_violation = :log) — test and
  # production both *raise*, because that is Rails' default.
  #
  # That combination is a trap for state-changing methods that notify someone or
  # emit an activity event. They run `update!` first and then read an
  # association to find the recipient. When the record was loaded by id — a
  # controller action, a PSP webhook, a background job — nothing is preloaded,
  # so the read raises *after* the write has already committed. The state change
  # sticks, the notification is silently lost, and the caller gets a 500. Live
  # examples found in this codebase: Marketplace::Order#mark_paid! (a real
  # Stripe payment recorded, both parties unnotified, 500 back to Stripe, and
  # the retry skipped because the order was no longer payable?),
  # Takeaway::Order#transition_to!, and the Tv activity emitters.
  #
  # This resolves by foreign key instead, and keeps the zero-extra-query fast
  # path when the caller did preload. It is not a licence to skip preloading —
  # `includes` is still correct at the query site, and prevents the N+1 that
  # strict loading exists to catch. This is the safety net for the paths where
  # a missed notification is worse than an extra SELECT.
  module StrictSafeAssociations
    extend ActiveSupport::Concern

    private

    def strict_safe(name)
      return public_send(name) if association(name).loaded?

      reflection = self.class.reflect_on_association(name)
      unless reflection&.belongs_to?
        raise ArgumentError, "strict_safe(#{name.inspect}) needs a belongs_to on #{self.class.name}"
      end

      foreign_key = public_send(reflection.foreign_key)
      return nil if foreign_key.nil?

      reflection.klass.strict_loading(false).find_by(id: foreign_key)
    end

    # Single column off a belongs_to, without instantiating the record at all.
    # For notification bodies that only need e.g. a title or a name.
    def strict_safe_attribute(name, column)
      return public_send(name)&.public_send(column) if association(name).loaded?

      reflection = self.class.reflect_on_association(name)
      unless reflection&.belongs_to?
        raise ArgumentError, "strict_safe_attribute(#{name.inspect}) needs a belongs_to on #{self.class.name}"
      end

      foreign_key = public_send(reflection.foreign_key)
      return nil if foreign_key.nil?

      reflection.klass.where(id: foreign_key).pick(column)
    end
  end
end
