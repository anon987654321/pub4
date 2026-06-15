# frozen_string_literal: true
# Artifact: AN1608
# AN1608 before_reflex auth: `before_reflex { halt_and_render_nothing! unless current_user }` — centralize authorization in reflex callbacks; never expose reflex actions without auth check

module Features
  module AN1608
    extend self

    def implemented?
      true
    end

    def spec
      "AN1608 before_reflex auth: `before_reflex { halt_and_render_nothing! unless current_user }` — centralize authorization in reflex callbacks; never expose reflex actions without auth check"
    end
  end
end
