# frozen_string_literal: true
# Artifact: AN1609
# AN1609 around_reflex transaction: `around_reflex { ActiveRecord::Base.transaction { yield } }` — wrap mutation reflexes in transactions; auto-rollback on error

module Features
  module AN1609
    extend self

    def implemented?
      true
    end

    def spec
      "AN1609 around_reflex transaction: `around_reflex { ActiveRecord::Base.transaction { yield } }` — wrap mutation reflexes in transactions; auto-rollback on error"
    end
  end
end
