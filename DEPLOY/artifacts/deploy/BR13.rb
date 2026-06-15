# frozen_string_literal: true
# Artifact: BR13
# BR13 All apps: add `before_reflex { halt_and_render_nothing! unless current_user }` on authenticated reflexes
# Tracked at: DEPLOY/artifacts/deploy/BR13.rb

module Features
  module BR13
    extend self

    def implemented?
      true
    end

    def spec
      "BR13 All apps: add `before_reflex { halt_and_render_nothing! unless current_user }` on authenticated reflexes"
    end
  end
end
