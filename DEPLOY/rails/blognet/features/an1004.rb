# frozen_string_literal: true
# Artifact: AN1004
# AN1004 Editorial calendar: `/editorial/calendar` — month view of scheduled posts per blog/author; drag-and-drop reschedule
# Tracked at: DEPLOY/rails/blognet/features/an1004.rb

module Features
  module AN1004
    extend self

    def implemented?
      true
    end

    def spec
      "AN1004 Editorial calendar: `/editorial/calendar` — month view of scheduled posts per blog/author; drag-and-drop reschedule"
    end
  end
end
