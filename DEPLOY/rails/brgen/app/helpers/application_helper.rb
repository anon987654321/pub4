# frozen_string_literal: true

module ApplicationHelper
  def lazy_image_tag(source, alt:, blurhash: nil, **options)
    image_options = options.dup
    image_options[:loading] ||= "lazy"
    blurhash ||= source.try(:blurhash) || source.try(:blob).try(:blurhash) || source.try(:metadata).try(:[], "blurhash")
    image_options[:data] = (image_options[:data] || {}).merge(
      controller: "lazy-image",
      lazy_image_target: "image",
      lazy_image_src_value: url_for(source)
    )
    image_options[:data][:lazy_image_blurhash_value] = blurhash if blurhash.present?

    image_tag("data:image/gif;base64,R0lGODlhAQABAAAAACw=", alt: alt, **image_options)
  end

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

  def safe_http_link(label, url)
    safe_url = safe_http_url(url)
    return unless safe_url

    link_to label, safe_url, rel: "noopener noreferrer", target: "_blank"
  end

  def safe_http_url(url)
    uri = URI.parse(url.to_s.strip)
    return uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?

    nil
  rescue URI::InvalidURIError
    nil
  end

  def marketplace_subdomain
    Brgen::DomainRegistry::ENTRIES.find { |entry| entry.domain == Current.domain }&.marketplace_subdomain || "marketplace"
  end

  def marketplace_host
    "#{marketplace_subdomain}.#{Current.domain}"
  end

  def marketplace_root_url(**options)
    marketplace_marketplace_root_url(subdomain: marketplace_subdomain, host: Current.domain, **options)
  end

  def active_vertical
    Current.subapp || inferred_vertical_from_controller
  end

  def vertical_surface?
    active_vertical.present?
  end

  def body_surface_classes
    parts = %w[zen-minimal]
    parts << "vertical-#{active_vertical}" if active_vertical
    parts.join(" ")
  end

  def inferred_vertical_from_controller
    case controller_path
    when /\Amarketplace/ then :marketplace
    when /\Aplaylist/ then :playlist
    when /\Atakeaway/ then :takeaway
    when /\Atv/ then :tv
    when /\Adating/ then :dating
    when /\Amaps/ then :maps
    when /\Aconversations/, /\Amessages/, /\Atyping_indicators/ then :messenger
    else nil
    end
  end

  POSTPRO_PRESETS = PostproJob::VALID_PRESETS.freeze

  def media_polish_classes(attachment)
    return "" unless attachment&.attached?

    name = attachment.filename.to_s.downcase
    classes = []
    classes << "postpro-grade" if POSTPRO_PRESETS.any? { |preset| name.include?("_#{preset}") }
    classes << "repligen-hero" if name.match?(/masterpiece|repligen|flux|lora/)
    classes.join(" ")
  end

  def tv_media_image_classes(attachment)
    [ "tv-media-image", media_polish_classes(attachment) ].compact_blank.join(" ")
  end
end
