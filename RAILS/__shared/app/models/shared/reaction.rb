# frozen_string_literal: true

module Shared
  class Reaction < ApplicationRecord
    self.table_name = "reactions"

    KINDS = %w[like love laugh wow sad angry local].freeze

    belongs_to :user
    belongs_to :reactable, polymorphic: true

    validates :kind, inclusion: { in: KINDS }
    validates :user_id, uniqueness: { scope: %i[reactable_type reactable_id kind] }

    # No broadcast: nothing subscribes to shared:reactions:* and no
    # shared/reactions/_reaction partial exists, so an implicit broadcast could
    # only raise ActionView::MissingTemplate inside Solid Queue — never update a
    # page. When a subscriber and partial are added, restore this as an explicit
    # broadcast_replace_later_to(stream, partial:, target:). Pinned by
    # test/turbo_broadcast_contract_test.rb.
  end
end
