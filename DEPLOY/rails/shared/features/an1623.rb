# frozen_string_literal: true
# Artifact: AN1623
# AN1623 stimulus-timeago on all timestamps: replace all `time_ago_in_words` Ruby calls with `data-controller="stimulus-timeago"`; client-side live updating, no server round-trip

module Features
  module AN1623
    extend self

    def implemented?
      true
    end

    def spec
      "AN1623 stimulus-timeago on all timestamps: replace all `time_ago_in_words` Ruby calls with `data-controller=\"stimulus-timeago\"`; client-side live updating, no server round-trip"
    end
  end
end
