# frozen_string_literal: true

module Master
  module Plugins
    module AirSuperioritySupport
      class Analyzer
        def initialize(observed_at: Time.now.utc)
          @observed_at = observed_at
        end

        def wifi(rows, known)
          known_ids = known.filter_map { |row| row["bssid"].to_s.downcase unless row["bssid"].to_s.empty? }
          rows.filter_map do |row|
            bssid = row["bssid"].to_s.downcase
            next if bssid.empty? || known_ids.include?(bssid)

            Finding.new(
              kind: "unknown_wifi",
              severity: "advisory",
              details: "Wi-Fi network is not in the local known list",
              data: row,
              observed_at: @observed_at,
            )
          end
        end

        def bluetooth(rows, known)
          known_ids = known.filter_map { |row| row["address"].to_s.downcase unless row["address"].to_s.empty? }
          rows.filter_map do |row|
            address = row["address"].to_s.downcase
            next if address.empty? || known_ids.include?(address)

            Finding.new(
              kind: "unknown_bluetooth",
              severity: "advisory",
              details: "Bluetooth device is not in the local known list",
              data: row,
              observed_at: @observed_at,
            )
          end
        end
      end
    end
  end
end
