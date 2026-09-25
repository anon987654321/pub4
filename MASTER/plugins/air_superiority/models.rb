# frozen_string_literal: true

module Master
  module Plugins
    module AirSuperiority
      Observation = Data.define(:kind, :data, :observed_at)
      Finding = Data.define(:kind, :severity, :details, :data, :observed_at)
      ScanResult = Data.define(:wifi, :bluetooth, :errors, :complete, :observed_at)
    end
  end
end
