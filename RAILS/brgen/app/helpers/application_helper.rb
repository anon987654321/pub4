# frozen_string_literal: true

module ApplicationHelper
  # The city this request is for, resolved from the domain by
  # Brgen::DomainRegistry (oshlo.no -> Oslo, lndon.uk -> London). Copy must
  # interpolate this rather than name a city: pages.home_title was the literal
  # string "Bergen", so every city domain rendered "Bergen - Brgen" no matter
  # which city the request had already resolved to.
  def city_name = Current.city_name

  def lazy_image_tag(source, alt:, blurhash: nil, **options)
    # Reserved before the bytes arrive: intrinsic dimensions ride every call
    # through Shared::UiHelper#image_dimensions (caller options win).
    image_options = image_dimensions(source).merge(options)
    image_options[:loading] ||= "lazy"
    blurhash ||= source.try(:blurhash) || source.try(:blob).try(:blurhash) || source.try(:metadata).try(:[], "blurhash")
    image_options[:data] = (image_options[:data] || {}).merge(
      controller: "lazy-image",
      lazy_image_target: "image",
      lazy_image_src_value: main_app.url_for(source)
    )
    image_options[:data][:lazy_image_blurhash_value] = blurhash if blurhash.present?

    image_tag("data:image/gif;base64,R0lGODlhAQABAAAAACw=", alt: alt, **image_options)
  end

  def responsive_image_tag(attachment, alt:, widths: [ 400, 800, 1_200 ], sizes: "(max-width: 768px) 100vw, 800px", loading: "lazy", **options)
    image_options = image_dimensions(attachment).merge(options)
    image_options[:loading] ||= loading

    return image_tag(attachment, alt: alt, **image_options) unless attachment.respond_to?(:variant)

    widths = Array(widths).map(&:to_i).uniq.sort
    largest = widths.last
    webp_srcset = widths.map do |width|
      "#{main_app.url_for(attachment.variant(resize_to_limit: [ width, width ], format: :webp))} #{width}w"
    end.join(", ")
    fallback_srcset = widths.map do |width|
      "#{main_app.url_for(attachment.variant(resize_to_limit: [ width, width ]))} #{width}w"
    end.join(", ")

    content_tag(:picture) do
      safe_join(
        [
          tag.source(type: "image/webp", srcset: webp_srcset, sizes: sizes),
          image_tag(
            # main_app.url_for: rendered inside isolated engines (tv/marketplace cards),
            # image_tag would otherwise resolve the variant against engine routes that
            # do not own ActiveStorage → to_model on VariantWithRecord. See ENGINES.md.
            main_app.url_for(attachment.variant(resize_to_limit: [ largest, largest ])),
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

  # ENTRIES_BY_DOMAIN is the frozen index of the same rows. The linear find this
  # replaced ran per record through schema_url_for -> record_public_href, so a
  # 25-listing index page walked all 44 entries 25 times.
  #
  # affiliate_deals_for used to sit under this comment at zero indentation, with
  # its own paragraph run together with this one. It is Shared::AffiliateHelper
  # now, with the rest of the affiliate stack.
  def marketplace_subdomain
    Brgen::DomainRegistry::ENTRIES_BY_DOMAIN[Current.domain.to_s]&.marketplace_subdomain || "marketplace"
  end

  def marketplace_host
    "#{marketplace_subdomain}.#{Current.domain}"
  end

  def marketplace_root_url(**options)
    marketplace.root_url(
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
    # Operator order, 2026-08-17: Front AI Markedsplass Playlist Dating Takeaway
    # TV Maps Messenger. The marketplace is named in Norwegian here because that
    # is the name on its own host — markedsplass.brgen.no — and the bar is the one
    # place all nine names sit together, so one of them reading in English was the
    # only one that did.
    [
      [ "front", main_app.root_path ],
      # live (the hyperlocal anonymous layer) is off this bar per operator, 2026-08-17.
      # The surface stays — its route, controller and rate limit are untouched, and
      # _mobile_chrome and nearby still link to it. It is not one of the nine names.
      [ "AI", brgen_ai_url ],
      [ "markedsplass", "//#{marketplace_host}/" ],
      [ "playlist", "//playlist.#{domain}/" ],
      [ "dating", "//dating.#{domain}/" ],
      [ "takeaway", "//takeaway.#{domain}/" ],
      [ "TV", "//tv.#{domain}/" ],
      [ "maps", "//maps.#{domain}/" ],
      [ "messenger", "//messenger.#{domain}/" ],
      [ "channels", main_app.channels_path ],
      *(authenticated? ? [] : [ [ "sign up", main_app.new_user_path ] ])
    ]
  end

  VERTICAL_NAV_LABELS = %w[markedsplass dating playlist TV takeaway maps messenger].freeze

  # brgen_nav_items chunked into two Hick's-law-sized groups for the swiper:
  # platform links, then the seven verticals. Keeps each group at or under 7
  # peer choices instead of one flat 10-11 item row.
  def brgen_nav_groups
    verticals, platform = brgen_nav_items.partition { |label, _| VERTICAL_NAV_LABELS.include?(label) }
    [ [ "brgen", platform ], [ "explore", verticals ] ]
  end

  def active_vertical
    Current.subapp || inferred_vertical_from_controller
  end

  # Which theme a surface is, decided per vertical rather than per visitor
  # (operator, 2026-08-24). These are product decisions — markedsplass and
  # takeaway are storefronts and read light, the media and social surfaces read
  # dark — not preferences, so prefers-color-scheme does not get a vote.
  #
  # The layout used to hardcode data-theme="dark" for every surface, which
  # pinned the three light verticals to the wrong palette: markedsplass measured
  # a dark ground under the light tokens its own accents are tuned against.
  # Anything not listed inherits brgen's dark default.
  #
  # maps rejoined on 2026-08-24 with its basemap. The note here used to say the
  # MapLibre basemap was dark and that pinning the dialect dark was therefore
  # correct. It was not: the app loads openfreemap positron, background
  # rgb(242,243,240), and loaded liberty at #f8f4f0 before that. Both light. The
  # shell was drawing dark chrome around a light map.
  LIGHT_VERTICALS = %i[marketplace maps takeaway].freeze

  def surface_theme
    LIGHT_VERTICALS.include?(active_vertical&.to_sym) ? "light" : "dark"
  end

  # The wordmark names the host it is actually on.
  #
  # It was the literal "brgen" on every surface, so Oslo, Stavanger, Trondheim,
  # Cardiff, Edinburgh and Frankfurt all wore Bergen's name, and every vertical
  # wore it too — markedsplass and dating were indistinguishable from the city
  # apex they hang off. One mark still, not seven: the city label keeps the
  # weight and the wordmark's letterspacing, and the subdomain and TLD are set
  # quieter around it, so the shape a reader recognises is unchanged and the
  # thing it now says is true.
  #
  # Current.domain is the city domain the request resolved to (brgen.no,
  # lsangeles.com), so this follows the registry rather than parsing the host a
  # second time and disagreeing with it.
  def brand_mark_fragments
    domain = Current.domain.presence || "brgen.no"
    city, _, tld = domain.partition(".")
    return { label: city } unless vertical_surface?

    # The host's own subdomain, not the subapp key: the two differ wherever an
    # alias is in play — markedsplass.brgen.no resolves to :marketplace, and the
    # mark should say what the reader typed.
    subdomain = Brgen::DomainRegistry.subdomain_for(
      Brgen::DomainRegistry.normalize_host(request&.host), domain
    )
    return { label: city } if subdomain.blank?

    { prefix: "#{subdomain}.", label: city, suffix: ".#{tld}" }
  end

  # Where the mark goes when you click it.
  #
  # main_app.root_path is "/" on every host, and on a vertical "/" is that
  # vertical — so the mark reading "dating.brgen.no" reloaded dating. On
  # markedsplass that was merely redundant, because its nav swiper carries
  # eleven other destinations. On dating it was a dead end: dating renders no
  # primary nav at all (operator, 2026-08-25), so the wordmark is the only
  # chrome on the page and it did not lead anywhere.
  #
  # The city apex is the honest target. It is the word the mark emphasises —
  # "brgen" keeps the weight, the subdomain and TLD recede around it — so
  # sending the click to the city is what the mark already looks like it does.
  def brand_mark_href
    return main_app.root_path unless vertical_surface?

    domain = Current.domain.presence
    return main_app.root_path if domain.blank?

    "#{request&.protocol || 'https://'}#{domain}/"
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
  # Distinguishes "no branch claimed this class" from "the branch claimed it and
  # there is no link" — a Message with no conversation, a Dating::Profile that is
  # not yours. Both are nil, and only the first may fall through to
  # polymorphic_path.
  UNROUTED = Object.new.freeze

  def record_public_href(record)
    return if record.blank?

    domain = Current.domain.presence || (respond_to?(:request) ? request.host : nil) || "brgen.no"
    href = apex_href(record, domain)
    href = engine_href(record, domain) if href == UNROUTED
    return href unless href == UNROUTED

    polymorphic_path(record) if respond_to?(:polymorphic_path)
  rescue StandardError # scan: intentional — an unroutable record renders unlinked, which is the correct degradation
    nil
  end

  # The city apex: everything served from the host itself rather than a vertical.
  def apex_href(record, domain)
    case record
    when Event then main_app.event_url(record, host: domain)
    when Story then main_app.story_url(record, host: domain)
    when Post then main_app.post_path(record)
    when Community then main_app.community_path(record)
    when Comment then record.commentable.present? ? polymorphic_path(record.commentable) : nil
    when User then main_app.user_path(record)
    when Message then main_app.conversation_path(record.conversation) if record.try(:conversation)
    when Conversation
      record.channel? ? main_app.channel_path(record.slug) : main_app.conversation_path(record)
    when Follow
      main_app.user_path(record.follower) if record.try(:follower)
    else UNROUTED
    end
  end

  # The mountable verticals, each on its own subdomain of the same city host.
  def engine_href(record, domain)
    case record
    when Marketplace::Listing
      marketplace.listing_url(record, host: domain, subdomain: marketplace_subdomain)
    when Marketplace::Store
      marketplace.shop_url(record.try(:slug) || record, host: domain, subdomain: marketplace_subdomain)
    when Marketplace::Deal
      marketplace.deal_url(record, host: domain, subdomain: marketplace_subdomain)
    when Marketplace::Order
      marketplace.order_url(record, host: domain, subdomain: marketplace_subdomain)
    when Takeaway::Restaurant
      takeaway.restaurant_url(record, host: domain, subdomain: "takeaway")
    when Takeaway::Order
      takeaway.order_url(record, host: domain, subdomain: "takeaway")
    when Place
      maps.place_url(record, host: domain, subdomain: "maps")
    when Dating::Match
      dating.matches_url(host: domain, subdomain: "dating")
    when Dating::Profile
      dating.profile_url(host: domain, subdomain: "dating") if record.user_id == Current.user&.id
    else media_href(record, domain)
    end
  end

  # tv and playlist, split off only because engine_href was over the length
  # ceiling with them in it.
  def media_href(record, domain)
    case record
    when Tv::Channel
      tv.channel_url(record, host: domain, subdomain: "tv")
    when Tv::Video
      tv.video_url(record, host: domain, subdomain: "tv")
    when Tv::Show
      ch = record.try(:channel) || record.try(:tv_channel)
      tv.channel_show_url(ch, record, host: domain, subdomain: "tv") if ch
    when Tv::LiveStream
      tv.live_stream_url(record, host: domain, subdomain: "tv")
    when Playlist::Set
      playlist.set_url(record, host: domain, subdomain: "playlist")
    when Playlist::Playlist
      playlist.playlist_url(record, host: domain, subdomain: "playlist")
    else UNROUTED
    end
  end

  # Deep link for an ActivityEvent row (object_type + object_id).
  def activity_event_href(event)
    return if event.blank? || event.object_type.blank? || event.object_id.blank?

    # Reuse the subject a batch loader already fetched (ActivityEvent
    # .for_city_home); only fall back to a lookup when the event arrived from
    # somewhere that did not preload one.
    record = event.activity_subject if event.respond_to?(:activity_subject)
    if record.nil?
      klass = event.object_type.to_s.safe_constantize
      return unless klass

      record = klass.find_by(id: event.object_id)
    end
    record_public_href(record)
  end

  def activity_event_title(event)
    return "" if event.blank?

    record = event.activity_subject if event.respond_to?(:activity_subject)
    if record.nil? && event.object_type.present?
      record = event.object_type.to_s.safe_constantize&.find_by(id: event.object_id)
    end
    name = record.try(:title).presence || record.try(:name).presence
    return name if name.present?

    key = event.event_name.to_s.underscore
    I18n.t("activity.#{key}", default: key.tr("_", " ").capitalize)
  end

  def activity_event_vertical(event)
    key = event.source_vertical.to_s
    return "" if key.blank?

    I18n.t("activity.verticals.#{key}", default: key)
  end

  # Deep link for a Notification — prefers notifiable, then source_*, then kind.
  def notification_href(notification)
    return if notification.blank?

    domain = Current.domain.presence || (respond_to?(:request) ? request.host : nil) || "brgen.no"

    case notification.kind.to_s
    when "match"
      return dating.matches_url(host: domain, subdomain: "dating")
    when "follow"
      return main_app.user_path(notification.actor) if notification.actor
    when "message"
      if notification.notifiable.is_a?(Message)
        return main_app.conversation_path(notification.notifiable.conversation)
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

    main_app.user_path(notification.actor) if notification.actor
  rescue StandardError # scan: intentional — an actor without a route renders unlinked
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
