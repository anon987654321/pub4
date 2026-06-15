# frozen_string_literal: true

module NorwegianFormatHelper
  def format_nok(amount)
    number_to_currency(amount, unit: "kr", separator: ",", delimiter: " ", format: "%n %u")
  end

  def format_norwegian_date(date)
    date&.strftime("%d.%m.%Y")
  end
end