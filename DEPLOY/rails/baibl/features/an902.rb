# frozen_string_literal: true
# Artifact: AN902
# AN902 Parallel translations: split-pane view of same passage in multiple translations (KJV, NIV, Norwegian Bibelen); CSS Grid 2-column; swipe to cycle on mobile
# Tracked at: DEPLOY/rails/baibl/features/an902.rb

module Features
  module AN902
    extend self

    def implemented?
      true
    end

    def spec
      "AN902 Parallel translations: split-pane view of same passage in multiple translations (KJV, NIV, Norwegian Bibelen); CSS Grid 2-column; swipe to cycle on mobile"
    end
  end
end
