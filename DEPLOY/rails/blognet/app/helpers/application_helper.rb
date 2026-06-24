# frozen_string_literal: true

module ApplicationHelper
  def responsive_image_tag(attachment, alt:, widths: [ 400, 800, 1_200 ], sizes: "(max-width: 768px) 100vw, 800px", loading: "lazy", **options)
    image_options = options.dup
    image_options[:loading] ||= loading

    return image_tag(attachment, alt: alt, **image_options) unless attachment.respond_to?(:variant)

    widths = Array(widths).map(&:to_i).uniq.sort
    largest = widths.last
    webp_srcset = widths.map do |width|
      "#{url_for(attachment.variant(resize_to_limit: [ width, width ], format: :webp))} #{width}w"
    end.join(", ")
    fallback_srcset = widths.map do |width|
      "#{url_for(attachment.variant(resize_to_limit: [ width, width ]))} #{width}w"
    end.join(", ")

    content_tag(:picture) do
      safe_join(
        [
          tag.source(type: "image/webp", srcset: webp_srcset, sizes: sizes),
          image_tag(
            attachment.variant(resize_to_limit: [ largest, largest ]),
            alt: alt,
            srcset: fallback_srcset,
            sizes: sizes,
            **image_options
          )
        ]
      )
    end
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
    minutes = [ (words / 220.0).ceil, 1 ].max
    "#{minutes} min read"
  end
end
