# frozen_string_literal: true

module ApplicationHelper
  def responsive_image_tag(attachment, alt:, widths: [400, 800, 1_200], sizes: "(max-width: 768px) 100vw, 800px", **options)
    return image_tag(attachment, alt: alt, **options) unless attachment.respond_to?(:variant)

    widths = Array(widths).map(&:to_i).uniq.sort
    largest = widths.last
    srcset = widths.map do |width|
      "#{url_for(attachment.variant(resize_to_limit: [width, width]))} #{width}w"
    end.join(", ")

    image_tag(
      attachment.variant(resize_to_limit: [largest, largest]),
      alt: alt,
      srcset: srcset,
      sizes: sizes,
      **options
    )
  end

  def nok(amount)
    number_to_currency(amount, unit: "kr", separator: ",", delimiter: " ", format: "%n %u")
  end

  def norwegian_date(value)
    l(value.to_date, format: "%d.%m.%Y")
  end

  def api_date(value)
    value.to_date.iso8601
  end

  def reading_time_for(text)
    words = ActionView::Base.full_sanitizer.sanitize(text.to_s).split.size
    minutes = [(words / 220.0).ceil, 1].max
    "#{minutes} min read"
  end
end
