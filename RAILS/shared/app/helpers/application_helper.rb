# frozen_string_literal: true

module ApplicationHelper
  include SchemaHelper
  include Shared::SeoKit

  def nok(amount)
    number_to_currency(amount, unit: "kr", separator: ",", delimiter: " ", format: "%n %u")
  end

  def norwegian_date(value)
    l(value.to_date, format: "%d.%m.%Y")
  end

  def api_date(value)
    value.to_date.iso8601
  end
end
