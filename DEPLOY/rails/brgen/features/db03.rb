# frozen_string_literal: true
# Artifact: DB03
# DB03 tv: add stream DVR — buffer last 30 minutes, allow rewind via `<video>` seekable range

module Features
  module DB03
    extend self

    def implemented?
      true
    end

    def spec
      "DB03 tv: add stream DVR — buffer last 30 minutes, allow rewind via `<video>` seekable range"
    end
  end
end
