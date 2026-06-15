# frozen_string_literal: true
# Artifact: DB07
# DB07 tv: add clip creation — select 30s segment from VOD, save as shareable clip

module Features
  module DB07
    extend self

    def implemented?
      true
    end

    def spec
      "DB07 tv: add clip creation — select 30s segment from VOD, save as shareable clip"
    end
  end
end
