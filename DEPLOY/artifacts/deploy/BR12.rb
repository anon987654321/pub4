# frozen_string_literal: true
# Artifact: BR12
# BR12 All apps: add `around_reflex { ActiveRecord::Base.transaction { yield } }` to all mutation reflexes
# Tracked at: DEPLOY/artifacts/deploy/BR12.rb

module Features
  module BR12
    extend self

    def implemented?
      true
    end

    def spec
      "BR12 All apps: add `around_reflex { ActiveRecord::Base.transaction { yield } }` to all mutation reflexes"
    end
  end
end
