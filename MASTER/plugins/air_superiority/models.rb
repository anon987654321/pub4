# frozen_string_literal: true

module Master
  module Plugins
    module AirSuperioritySupport
      Observation = Data.define(:kind, :data, :observed_at)
      Finding = Data.define(:kind, :severity, :details, :data, :observed_at)
      ScanResult = Data.define(:wifi, :bluetooth, :errors, :complete, :observed_at)
    end
  end
end
