# frozen_string_literal: true

class PortsSearch
  COLUMNS = %w[name summary description].freeze

  def self.call(query:, scope: Port.all)
    Shared::LiveSearch.search(scope, query:, columns: COLUMNS, vertical: "ports", app: "bsdports").scope.order(:name)
  end
end
