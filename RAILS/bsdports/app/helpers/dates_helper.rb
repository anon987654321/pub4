# frozen_string_literal: true

module DatesHelper
  # A localised date in a <time> carrying the machine value; nil stays empty.
  def date_tag(value)
    return if value.nil?

    tag.time l(value.to_date), datetime: value.iso8601
  end
end
