# frozen_string_literal: true
# Artifact: AN1207
# AN1207 Fragment caching: `cache [@post, current_user]` for post cards; key includes user to handle voted/unvoted state; Russian doll for comment trees
# Tracked at: DEPLOY/rails/shared/features/an1207.rb

module Features
  module AN1207
    extend self

    def implemented?
      true
    end

    def spec
      "AN1207 Fragment caching: `cache [@post, current_user]` for post cards; key includes user to handle voted/unvoted state; Russian doll for comment trees"
    end
  end
end
