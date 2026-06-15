# frozen_string_literal: true
# Artifact: DB01
# DB01 tv: add HLS stream ingestion — accept RTMP from OBS, segment and serve via httpd

module Features
  module DB01
    extend self

    def implemented?
      true
    end

    def spec
      "DB01 tv: add HLS stream ingestion — accept RTMP from OBS, segment and serve via httpd"
    end
  end
end
