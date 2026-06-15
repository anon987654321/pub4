# frozen_string_literal: true

require "csv"

module Shared
  module AccountExporter
    module_function

    def to_csv(user)
      CSV.generate do |csv|
        csv << %w[field value]
        csv << ["email", user.email_address]
        csv << ["created_at", user.created_at]
        csv << ["id", user.id]
      end
    end
  end
end