# frozen_string_literal: true

module Brgen
  class SeedCities
    def self.sync!
      Brgen::CitySeed.sync!
    end
  end
end
