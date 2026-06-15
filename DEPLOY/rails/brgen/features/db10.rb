# frozen_string_literal: true
# Artifact: DB10
# DB10 tv: add embed code for streams (`<iframe>`) with CORS allow-list

module Features
  module DB10
    extend self

    def implemented?
      true
    end

    def spec
      "DB10 tv: add embed code for streams (`<iframe>`) with CORS allow-list"
    end
  end
end
