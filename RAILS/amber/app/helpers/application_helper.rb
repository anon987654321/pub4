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
# vm23 no Solid Queue supervisor is resident for this app: TODO.md
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

    # The named-variant path is amber's alone — brgen preprocesses no presets —
    # so it stays in front of the shared <picture>, never inside it.
    if widths.blank? && named_variant_preset?(attachment, preset)
      return named_responsive_image_tag(attachment, alt: alt, preset: preset, sizes: sizes, **image_options)
    end

    # Ambient url_for, and image_tag gets the variant object: amber mounts no
    # engines, so there is no main_app indirection to route around the way
    # brgen needs one.
    responsive_picture_tag(
      attachment,
      alt: alt,
      widths: widths.presence || [ 400, 800, 1_200 ],
      sizes: sizes,
      srcset_url: ->(variant) { url_for(variant) },
      **image_options
    )
  end

  def current_creator_profile
    return unless Current.user

    CreatorProfile.find_by(user: Current.user)
  end

  # A garment's colour, and the ink that reads on it.
  #
  # One map rather than two, because the second value only makes sense beside
  # the first: the swatch stands in for a missing photograph, so it is whatever
  # colour the garment is, and no single ink survives that. The note beside
  # .wardrobe_slide_glyph said the swatches "are chosen light enough to carry"
  # --text, which held for six of these ten and not for the other four —
  # measured against #333333, charcoal ran 1.21, navy 1.36, tortoise 2.26 and
  # terracotta 3.42, all under the 4.5 floor for the 18px name they carry.
  #
  # Black or white, whichever sits further from the swatch. The worst case
  # across the map is terracotta at 5.11 and the best is ivory at 17.91.
  # amber_swatch_ink_test pins every pair with Deploy::DesignMetrics::Contrast,
  # so the numbers here are checked by the one implementation of that maths this
  # repo trusts rather than restated by hand.
  WARDROBE_SWATCHES = [
    [/navy|indigo/, "#3c4858", "#ffffff"],
    [/black|charcoal/, "#3c4043", "#ffffff"],
    [/white|ivory|oatmeal|cream|pearl/, "#f8f9fa", "#111111"],
    [/blush|rose|mauve/, "#f6d6d9", "#111111"],
    [/sage|olive/, "#c8d5b9", "#111111"],
    [/rust|terracotta/, "#c96b4b", "#111111"],
    [/camel|tan|gold/, "#d4a574", "#111111"],
    [/nude/, "#e8d2c5", "#111111"],
    [/tortoise/, "#8b5e3c", "#ffffff"],
  ].freeze

  WARDROBE_SWATCH_DEFAULT = ["#e8eaed", "#111111"].freeze

  def wardrobe_color_swatch(color)
    wardrobe_swatch_pair(color).first
  end

  def wardrobe_swatch_ink(color)
    wardrobe_swatch_pair(color).last
  end

  def wardrobe_swatch_pair(color)
    name = color.to_s.downcase
    match = WARDROBE_SWATCHES.find { |pattern, _swatch, _ink| pattern.match?(name) }
    return WARDROBE_SWATCH_DEFAULT unless match

    [match[1], match[2]]
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
