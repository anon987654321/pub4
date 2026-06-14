# frozen_string_literal: true

module Shared
  module CableHealth
    ALERT_THRESHOLD = 1_000

    def self.alert?(connection_count:, max_connections:)
      return false if max_connections.to_i <= 0

      connection_count.to_i >= max_connections.to_i
    end

    def self.connection_count(server: nil)
      server ||= ActionCable.server if defined?(ActionCable)
      return 0 unless server

      connections = server.respond_to?(:connections) ? server.connections : []
      connections.respond_to?(:size) ? connections.size : Array(connections).size
    rescue StandardError
      0
    end

    def self.message(app:, connection_count:, max_connections:)
      "#{app} cable at #{connection_count}/#{max_connections} connections"
    end
  end
end
