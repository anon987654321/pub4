# frozen_string_literal: true

module MoneyInOre
  extend ActiveSupport::Concern

  class_methods do
    def money_reader(column)
      cents_col = "#{column}_cents"

      define_method(column) do
        cents = public_send(cents_col)
        cents.nil? ? nil : cents / 100.0
      end

      define_method("#{column}?") do
        public_send(cents_col).present?
      end

      define_method("#{column}=") do |value|
        self.public_send(
          "#{cents_col}=",
          value.blank? ? nil : (BigDecimal(value.to_s) * 100).round.to_i
        )
      end
    end
  end
end