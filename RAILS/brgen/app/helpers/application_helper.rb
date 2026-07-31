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
          ),
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
    Rails.application.routes.url_helpers.marketplace_root_url(
      subdomain: marketplace_subdomain,
      host: Current.domain,
      **options
    )
  end

  def brgen_ai_url
    Rails.application.config.x.master_web_url
  end

  # Primary vertical navigation for the pull-down swiper. front → home feed;
  # AI → the shared MASTER face; the rest are per-city verticals on subdomains.
  def brgen_nav_items
    domain = Current.domain
    [
      ["front", root_path],
      ["live", live_path],
      ["AI", brgen_ai_url],
      ["marketplace", "//#{marketplace_host}/"],
      ["dating", "//dating.#{domain}/"],
      ["playlist", "//playlist.#{domain}/"],
      ["TV", "//tv.#{domain}/"],
      ["takeaway", "//takeaway.#{domain}/"],
      ["maps", "//maps.#{domain}/"],
      ["messenger", "//messenger.#{domain}/"],
      ["channels", channels_path],
      *(authenticated? ? [] : [["sign up", new_session_path]])
    ]
  end

  VERTICAL_NAV_LABELS = %w[marketplace dating playlist TV takeaway maps messenger].freeze

  # brgen_nav_items chunked into two Hick's-law-sized groups for the swiper:
  # platform links, then the seven verticals. Keeps each group at or under 7
  # peer choices instead of one flat 10-11 item row.
  def brgen_nav_groups
    verticals, platform = brgen_nav_items.partition { |label, _| VERTICAL_NAV_LABELS.include?(label) }
    [["brgen", platform], ["explore", verticals]]
  end

  def subapp_nav_items
    brgen_nav_items.select { |label, _| VERTICAL_NAV_LABELS.include?(label) }
  end

  def active_vertical
    Current.subapp || inferred_vertical_from_controller
  end

  def home_feed_following?
    Brgen::HomeFeed.following?(feed: params[:feed])
  end

  def vertical_surface?
    active_vertical.present?
  end

  def body_surface_classes
    parts = []
    parts << "vertical-#{active_vertical}" if active_vertical
    parts << "auth-surface" if auth_surface?
    parts.join(" ")
  end

  # Sign-in / sign-up / password reset — chrome-light body (no tab bar, nearby, edge grips).
  def auth_surface?
    controller_path.in?(%w[sessions passwords users two_factor_setups])
  end

  def inferred_vertical_from_controller
    case controller_path
    when /\Amarketplace/ then :marketplace
    when /\Aplaylist/ then :playlist
    when /\Atakeaway/ then :takeaway
    when /\Atv/ then :tv
    when /\Adating/ then :dating
    when /\Amaps/ then :maps
    # Public IRC channels share messenger chrome (slate-indigo immersive).
    when /\Aconversations/, /\Amessages/, /\Atyping_indicators/, /\Achannels/ then :messenger
    else nil
    end
  end

  # Public href for a domain record. Vertical models use absolute subdomain URLs
  # so apex surfaces (activity, notifications) can open the right host.
  def record_public_href(record)
    return if record.blank?

    domain = Current.domain.presence || (respond_to?(:request) ? request.host : nil) || "brgen.no"
    case record
    when Post then post_path(record)
    when Community then community_path(record)
    when Comment then record.commentable.present? ? polymorphic_path(record.commentable) : nil
    when User then user_path(record)
    when Message then conversation_path(record.conversation) if record.try(:conversation)
    when Conversation
      record.channel? ? channel_path(record.slug) : conversation_path(record)
    when Marketplace::Listing
      marketplace_listing_url(record, host: domain, subdomain: marketplace_subdomain)
    when Marketplace::Store
      marketplace_shop_url(record.try(:slug) || record, host: domain, subdomain: marketplace_subdomain)
    when Marketplace::Deal
      marketplace_deal_url(record, host: domain, subdomain: marketplace_subdomain)
    when Marketplace::Order
      marketplace_order_url(record, host: domain, subdomain: marketplace_subdomain)
    when Takeaway::Restaurant
      takeaway_restaurant_url(record, host: domain, subdomain: "takeaway")
    when Takeaway::Order
      takeaway_order_url(record, host: domain, subdomain: "takeaway")
    when Tv::Channel
      tv_channel_url(record, host: domain, subdomain: "tv")
    when Tv::Video
      tv_video_url(record, host: domain, subdomain: "tv")
    when Tv::Show
      ch = record.try(:channel) || record.try(:tv_channel)
      tv_channel_show_url(ch, record, host: domain, subdomain: "tv") if ch
    when Tv::LiveStream
      tv_live_stream_url(record, host: domain, subdomain: "tv")
    when Playlist::Set
      playlist_set_url(record, host: domain, subdomain: "playlist")
    when Playlist::Playlist
      playlist_playlist_url(record, host: domain, subdomain: "playlist")
    when Place
      maps_place_url(record, host: domain, subdomain: "maps")
    when Dating::Match
      dating_matches_url(host: domain, subdomain: "dating")
    when Dating::Profile
      dating_profile_url(host: domain, subdomain: "dating") if record.user_id == Current.user&.id
    when Follow
      user_path(record.follower) if record.try(:follower)
    else
      polymorphic_path(record) if respond_to?(:polymorphic_path)
    end
  rescue StandardError
    nil
  end

  # Deep link for an ActivityEvent row (object_type + object_id).
  def activity_event_href(event)
    return if event.blank? || event.object_type.blank? || event.object_id.blank?

    klass = event.object_type.to_s.safe_constantize
    return unless klass

    record = klass.find_by(id: event.object_id)
    record_public_href(record)
  end

  def activity_event_title(event)
    event.event_name.to_s.humanize
  end

  # Deep link for a Notification — prefers notifiable, then source_*, then kind.
  def notification_href(notification)
    return if notification.blank?

    domain = Current.domain.presence || (respond_to?(:request) ? request.host : nil) || "brgen.no"

    case notification.kind.to_s
    when "match"
      return dating_matches_url(host: domain, subdomain: "dating")
    when "follow"
      return user_path(notification.actor) if notification.actor
    when "message"
      if notification.notifiable.is_a?(Message)
        return conversation_path(notification.notifiable.conversation)
      elsif notification.notifiable.is_a?(Conversation)
        return record_public_href(notification.notifiable)
      end
    end

    href = record_public_href(notification.notifiable)
    return href if href.present?

    if notification.respond_to?(:source_type) && notification.source_type.present?
      klass = notification.source_type.to_s.safe_constantize
      src = klass&.find_by(id: notification.source_id)
      href = record_public_href(src)
      return href if href.present?
    end

    user_path(notification.actor) if notification.actor
  rescue StandardError
    nil
  end

  POSTPRO_PRESETS = PostproJob::VALID_PRESETS.freeze

  def media_polish_classes(attachment)
    return "" if attachment.blank?
    return "" if attachment.respond_to?(:attached?) && !attachment.attached?

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
