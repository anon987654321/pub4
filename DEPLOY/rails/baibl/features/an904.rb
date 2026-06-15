# frozen_string_literal: true
# Artifact: AN904
# AN904 Annotation layers: user creates private/public annotations on any verse; visible as margin notes; toggle annotation layers by author/group
# Tracked at: DEPLOY/rails/baibl/features/an904.rb

module Features
  module AN904
    extend self

    def implemented?
      true
    end

    def spec
      "AN904 Annotation layers: user creates private/public annotations on any verse; visible as margin notes; toggle annotation layers by author/group"
    end
  end
end
