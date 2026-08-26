# frozen_string_literal: true

module ApplicationHelper
  # Pagy::Frontend is gone in pagy 43 and amber calls no pagy_* helper — every
  # paginated view in all three apps renders through shared/_pager, which reads
  # the Pagy object directly. Including a module for helpers nothing calls was
  # the one line standing between this app and the version the others are on.

  # Named ActiveStorage presets preprocessed by WardrobeMediaJob. Prefer these
  # so list/detail pages do not invent resize_to_limit widths the job never built
  # (each invented size is a cold ruby-vips pass + variant_records miss).
  IMAGE_PRESETS = {
    thumb: [ [ :thumb, 240 ] ],
    card: [ [ :thumb, 240 ], [ :card, 720 ] ],
    detail: [ [ :thumb, 240 ], [ :card, 720 ] ]
  }.freeze

  def amber_ai_available?
    WardrobeAi.configured?
  end

  def master_photograph_available?
    WardrobeAi.master_photograph_available?
  end

# "Pending media" is only true while something is going to pick the job up.
#
# amber enqueues its media work — polish, fingerprinting, analysis — and on
# vm23 no Solid Queue supervisor is resident for this app: OPENBSD/data/debt.yml
# records the decision (1 GB, exactly one resident worker, brgen_jobs) and the
# rc.d footer measured 103 jobs enqueued and 0 finished. So a garment uploaded
# today shows "Pending media" and will show it forever, and the person who
# uploaded it has no way to learn that pending is the terminal state here.
#
# That is the shape payment_honesty, affiliate_honesty and content_honesty all
# exist to refuse: a label that describes an intention rather than a fact. When
# no worker is registered the label says so instead.
def analysis_status_label(status)
  key = case status.to_s
  when "photo_polish_done" then "photo_polish_done"
  when "photo_polish_failed" then "photo_polish_failed"
  when "photo_polish_skipped", "no_photos" then status.to_s
  when "pending" then media_worker_running? ? "pending" : "pending_no_worker"
  when /segmentation|background/ then "legacy"
  end
  return t("items.analysis.#{key}") if key

  status.to_s.humanize
end

# One query per request at most, and it degrades to "yes" rather than
# announcing an outage on its own: a missing table or an unreachable queue
# database is this check failing, not the worker being absent.
def media_worker_running?
  return @media_worker_running if defined?(@media_worker_running)

  @media_worker_running = Rails.cache.fetch("amber:queue:worker_present", expires_in: 1.minute) do
    SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).exists?
  rescue StandardError
    true
  end
end

  def live_stream_status_label(status)
    t("live_streams.status.#{status}", default: status.to_s)
  end

  # preset: :thumb | :card | :detail uses named variants when available.
  # widths: explicit list keeps the legacy multi-size path (avoid for wardrobe
  # grids — those sizes are not preprocessed).
  def responsive_image_tag(attachment, alt:, preset: :card, widths: nil, sizes: "(max-width: 768px) 100vw, 800px", loading: "lazy", **options)
    image_options = image_dimensions(attachment).merge(options)
    image_options[:loading] ||= loading

    return image_tag(attachment, alt: alt, **image_options) unless attachment.respond_to?(:variant)

    if widths.blank? && named_variant_preset?(attachment, preset)
      return named_responsive_image_tag(attachment, alt: alt, preset: preset, sizes: sizes, **image_options)
    end

    widths = Array(widths.presence || [ 400, 800, 1_200 ]).map(&:to_i).uniq.sort
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

  def current_creator_profile
    return unless Current.user

    CreatorProfile.find_by(user: Current.user)
  end

  def wardrobe_color_swatch(color)
    case color.to_s.downcase
    when /navy|indigo/ then "#3c4858"
    when /black|charcoal/ then "#3c4043"
    when /white|ivory|oatmeal|cream|pearl/ then "#f8f9fa"
    when /blush|rose|mauve/ then "#f6d6d9"
    when /sage|olive/ then "#c8d5b9"
    when /rust|terracotta/ then "#c96b4b"
    when /camel|tan|gold/ then "#d4a574"
    when /nude/ then "#e8d2c5"
    when /tortoise/ then "#8b5e3c"
    else "#e8eaed"
    end
  end

  def responsive_image_url(attachment, preset: :card, widths: [ 400, 800, 1_200 ])
    return url_for(attachment) unless attachment.respond_to?(:variant)

    if widths.blank? || named_variant_preset?(attachment, preset)
      name = IMAGE_PRESETS.fetch(preset.to_sym).last.first
      return url_for(attachment.variant(name))
    end

    largest = Array(widths).map(&:to_i).uniq.sort.last
    url_for(attachment.variant(resize_to_limit: [ largest, largest ]))
  end

  private

  def named_variant_preset?(attachment, preset)
    entries = IMAGE_PRESETS[preset.to_sym]
    return false unless entries

    # Probe the first named variant; undefined names raise and we fall back.
    attachment.variant(entries.first.first)
    true
  rescue ArgumentError, KeyError
    false
  end

  def named_responsive_image_tag(attachment, alt:, preset:, sizes:, **image_options)
    entries = IMAGE_PRESETS.fetch(preset.to_sym)
    srcset = entries.map { |name, width| "#{url_for(attachment.variant(name))} #{width}w" }.join(", ")
    largest_name = entries.last.first

    image_tag(
      attachment.variant(largest_name),
      alt: alt,
      srcset: srcset,
      sizes: sizes,
      **image_options
    )
  end
end
