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
    detail: [ [ :thumb, 240 ], [ :card, 720 ] ],
  }.freeze

  # aria-current for a nav link: "page" on the link's own page, "true" anywhere
  # else in its section, so items/123 still marks Wardrobe. current_page? alone
  # matched only the exact index path. except names actions with a link of
  # their own (the dressing room is outfits#dressing_room).
  def nav_current(path, section: nil, except: [])
    return "page" if current_page?(path)

    "true" if section == controller_name && except.exclude?(action_name)
  end

  def amber_ai_available?
    WardrobeAi.configured?
  end

  # Translate enum labels at the view boundary while keeping canonical values in forms.
  def amber_enum_options(values, scope:)
    values.map do |value|
      key = value.tr("-", "_").downcase
      [t("#{scope}.#{key}"), value]
    end
  end

  def amber_season_options = amber_enum_options(Item::SEASONS, scope: "outfits.seasons")

  # One stored enum value in the reader's language, keyed the way
  # amber_enum_options keys the select it was chosen from. An unknown value
  # prints as stored rather than raising.
  def amber_enum_label(value, scope:)
    return if value.blank?

    t("#{scope}.#{value.to_s.tr('-', '_').downcase}", default: value.to_s).upcase_first
  end

  def item_category_label(value) = amber_enum_label(value, scope: "items.item_categories")
  def lifecycle_state_label(value) = amber_enum_label(value, scope: "lifecycle_states")
  def mood_effect_label(value) = amber_enum_label(value, scope: "items.mood_effects")
  def life_phase_label(value) = amber_enum_label(value, scope: "items.life_phases")

  def amber_item_category_options = amber_enum_options(Item::CATEGORIES, scope: "items.item_categories")

  def amber_mood_effect_options = amber_enum_options(Item::MOOD_EFFECTS, scope: "items.mood_effects")

  def amber_life_phase_options = amber_enum_options(Item::LIFE_PHASES, scope: "items.life_phases")

  def studio_photograph_available?
    WardrobeAi.studio_photograph_available?
  end

# "Pending media" describes queued work, not immediate completion.
#
# vm23 runs Amber's Solid Queue jobs in bounded hourly drains rather than a
# resident supervisor; see OPENBSD/etc/crontab.vm23 and
# OPENBSD/usr/local/bin/drain-jobs.sh. A heartbeat means a worker is active now.
# No heartbeat means work awaits a later drain; a failed status query means the
# state is unknown. Keep those cases distinct in the interface.
def analysis_status_label(status)
  key = case status.to_s
  when "photo_polish_done" then "photo_polish_done"
  when "photo_polish_failed" then "photo_polish_failed"
  when "photo_polish_skipped", "no_photos" then status.to_s
  when "pending"
    case media_worker_running?
    when true then "pending"
    when false then "pending_no_worker"
    else "pending_unknown"
    end
  when /segmentation|background/ then "legacy"
  end
  return t("items.analysis.#{key}") if key

  status.to_s.humanize
end

# One query per request at most. Failure to read the queue is unknown, not
# evidence that a worker is either present or absent.
def media_worker_running?
  return @media_worker_running if defined?(@media_worker_running)

  @media_worker_running = Rails.cache.fetch("amber:queue:worker_present", expires_in: 1.minute) do
    SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).exists?
  rescue StandardError
    :unknown
  end
end

  # A garment worn at a known price, in kroner and in the reader's language.
  # nil when either is missing, so the caller leaves the figure out rather
  # than printing an unpriced garment as unworn.
  def cost_per_wear_label(item)
    return unless item.cost_per_wear

    t("items.per_wear", amount: number_to_currency(item.cost_per_wear))
  end

# [label, value] pairs for a declutter decision select; String#humanize
# only ever produced English.
def declutter_target_options(targets)
  targets.map { |target| [ t("declutter.targets.#{target}"), target ] }
end

  STYLE_PROFILE_ANSWERS = {
    "body_type" => %w[slim athletic curvy plus],
    "lines" => [ "minimal clean lines", "bold patterns and colors" ],
    "timeless" => [ "classic timeless pieces", "trendy current styles" ],
    "colors" => [ "neutrals and basics", "vibrant pops of color" ],
    "fit" => [ "tailored structured fits", "loose comfortable layers" ],
  }.freeze

  # [label, value] pairs for a style-profile question. The value is the
  # English phrase WardrobeAi reads; the label is the reader's language.
  def style_profile_options(question)
    STYLE_PROFILE_ANSWERS.fetch(question).map do |value|
      [ t("ai.style_options.#{question}.#{value.parameterize(separator: '_')}"), value ]
    end
  end

  # A DeclutterScore value as a reader sees it: 0..1 scores as a whole
  # percentage (not 0.437), the quadrant and the recommendation in words.
  def declutter_score_value(key, value)
    case key.to_sym
    when :quadrant then t("declutter.quadrants.#{value}", default: value.to_s.humanize)
    when :recommendation then t("declutter.targets.#{value}", default: value.to_s.humanize)
    else value.is_a?(Numeric) ? number_to_percentage(value * 100, precision: 0) : value
    end
  end

  # [title, id] for the outfit form's item picker, loaded once per form and
  # shared by the row template and every existing row, which each queried.
  def outfit_item_options
    Current.user.items.order(:title).pluck(:title, :id)
  end

  def live_stream_status_label(status)
    t("live_streams.status.#{status}", default: status.to_s)
  end

  # preset: :thumb | :card | :detail uses named variants when available.
  # widths: explicit list keeps the legacy multi-size path (avoid for wardrobe
  # grids — those sizes are not preprocessed).
  def responsive_image_tag(attachment, alt:, preset: :card, widths: nil, sizes: "(max-width: 768px) 100vw, 800px", loading: "lazy", **options)
    image_options = reserved_image_options(attachment, options, loading:)

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
    [ /navy|indigo/, "#3c4858", "#ffffff" ],
    [ /black|charcoal/, "#3c4043", "#ffffff" ],
    [ /white|ivory|oatmeal|cream|pearl/, "#f8f9fa", "#111111" ],
    [ /blush|rose|mauve/, "#f6d6d9", "#111111" ],
    [ /sage|olive/, "#c8d5b9", "#111111" ],
    [ /rust|terracotta/, "#c96b4b", "#111111" ],
    [ /camel|tan|gold/, "#d4a574", "#111111" ],
    [ /nude/, "#e8d2c5", "#111111" ],
    [ /tortoise/, "#8b5e3c", "#ffffff" ],
  ].freeze

  WARDROBE_SWATCH_DEFAULT = [ "#e8eaed", "#111111" ].freeze

  def wardrobe_color_swatch(color)
    wardrobe_swatch_pair(color).first
  end

  # A photo's alt and its lightbox link's name: the title for a lone photo,
  # "Wool coat, photo 2 of 3" when there are several.
  # index counts from 0, as each_with_index does.
  def item_photo_labels(item, index)
    count = item.photos.size
    return [ item.title, nil ] if count < 2

    numbered = { title: item.title, position: index + 1, count: }
    [ t("items.photo_numbered", **numbered), t("items.open_photo", **numbered) ]
  end

  # A garment's colour as an SVG dot. A fill attribute, not style="--swatch",
  # so pages with a swatch need no 'unsafe-inline' in style-src. Decorative
  # unless labelled: the colour's name is usually printed beside it.
  def wardrobe_swatch_tag(color, label: nil, small: false)
    dot = tag.circle(cx: 10, cy: 10, r: 10, fill: wardrobe_color_swatch(color))
    tag.svg(safe_join([ (tag.title(label) if label), dot ].compact),
            class: [ "color-swatch", ("color-swatch--sm" if small) ], viewBox: "0 0 20 20",
            role: ("img" if label), aria: label ? { label: } : { hidden: true })
  end

  def wardrobe_swatch_ink(color)
    wardrobe_swatch_pair(color).last
  end

  def wardrobe_swatch_pair(color)
    name = color.to_s.downcase
    match = WARDROBE_SWATCHES.find { |pattern, _swatch, _ink| pattern.match?(name) }
    return WARDROBE_SWATCH_DEFAULT unless match

    [ match[1], match[2] ]
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
