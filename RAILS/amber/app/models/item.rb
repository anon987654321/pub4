# frozen_string_literal: true

require "tempfile"

class Item < ApplicationRecord
  include MoneyInOre
  money_reader :price

  include Shared::Reactable
  include Shared::Notifiable
  belongs_to :user
  has_one :garment_embedding, dependent: :destroy
  has_one :sustainability_metric, dependent: :destroy
  has_one :declutter_review, dependent: :destroy
  has_one :declutter_outcome, dependent: :destroy
  has_many :outfit_items, dependent: :destroy
  has_many :outfits, through: :outfit_items
  has_many :wear_logs, dependent: :destroy
  has_many :affiliate_links, dependent: :destroy
  has_many :declutter_challenges, dependent: :destroy

  # Named variants match WardrobeMediaJob — keep dimensions in lockstep so
  # list/show helpers hit preprocessed digests instead of inventing new sizes.
  PHOTO_VARIANTS = {
    thumb: { resize_to_limit: [ 240, 240 ] },
    card: { resize_to_limit: [ 720, 960 ] }
  }.freeze

  has_many_attached :photos do |attachable|
    PHOTO_VARIANTS.each do |name, transformations|
      attachable.variant(name, **transformations)
    end
  end

  # photos_attachments + blob + variant_records so responsive_image_tag does not
  # N+1 variant lookups on grid/carousel pages (see wardrobe_showcase).
  scope :with_photos_for_display, -> {
    includes(photos_attachments: { blob: :variant_records })
  }

  validates :title, :category, presence: true
  validates :times_worn, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true

  # broadcasts_refreshes omitted on 1-CPU VPS: each save enqueues Turbo::Streams::BroadcastStreamJob
  # and media/AI pipelines touch items many times per upload (queue depth >> 1000).

  scope :joy,          -> { where(spark_joy: true) }
  scope :by_category,  ->(c) { where(category: c) }
  scope :by_mood,      ->(m) { where(mood_effect: m) }
  scope :by_occasion,  ->(o) { where("occasion_tags LIKE ?", "%#{sanitize_sql_like(o.to_s)}%") }
  scope :current_self, -> { where(life_phase: "current") }
  scope :recent,       -> { order(created_at: :desc) }
  scope :worn_most,    -> { order(times_worn: :desc) }
  scope :never_worn,   -> { where("times_worn = 0 OR times_worn IS NULL") }
  # The SQL twin of #underused? — kept adjacent so the threshold cannot drift
  # between the two. WardrobeAnalytics used to answer this by loading every
  # row and calling the Ruby predicate.
  scope :underused,    -> { where("COALESCE(times_worn, 0) < 3") }
  scope :aging_unworn, -> { never_worn.where("purchase_date < ?", 6.months.ago) }
  scope :embeddable,   -> { where.not(title: [ nil, "" ]).where.not(category: [ nil, "" ]) }
  scope :active_wardrobe, -> { where.not(lifecycle_state: %w[released donated sold recycled]) }
  # What is still in rotation: active_wardrobe minus the declutter box.
  #
  # The distinction matters for anything that *recommends* a garment. A boxed
  # item is one you have already decided about, and active_wardrobe keeps it —
  # so the dressing room offered it, the Style Assistant put it on you, and the
  # idle figure nagged you to wear it. Inventory figures still count it, because
  # you do still own it.
  scope :in_rotation, -> { active_wardrobe.where.not(lifecycle_state: "declutter_box") }
  scope :declutter_box, -> { where(lifecycle_state: "declutter_box") }
  scope :sentimental, -> { where(lifecycle_state: "sentimental_archive") }
  scope :seasonal_archived, -> { where(lifecycle_state: "seasonal_archive") }

  def self.for_lifecycle(key)
    case key.to_s
    when "all" then all
    when "box", "declutter_box" then declutter_box
    when "memory", "sentimental" then sentimental
    when "seasonal" then seasonal_archived
    when "repair" then where(lifecycle_state: "repair")
    else active_wardrobe
    end
  end

  CATEGORIES   = %w[Tops Bottoms Dresses Shoes Accessories Outerwear].freeze
  SEASONS      = %w[Spring Summer Autumn Winter All-Season].freeze
  MOOD_EFFECTS = %w[energising calming confident playful neutral].freeze
  LIFE_PHASES  = %w[current past-self aspirational].freeze
  OCCASIONS    = %w[work casual formal gym date travel].freeze
  LIFECYCLE_STATES = %w[active repair clean_needed tailor declutter_box sentimental_archive seasonal_archive resale donate sold donated recycled released].freeze

  def cost_per_wear
    return nil unless price_cents.present? && times_worn.to_i.positive?

    (price_cents / 100.0 / times_worn).round(2)
  end

  def value_label
    cost_per_wear ? "#{cost_per_wear} per wear" : "not worn yet"
  end

  def underused?
    times_worn.to_i < 3
  end

  def capsule_candidate?
    spark_joy? && !released? && !in_declutter_box?
  end

  def occasions
    occasion_tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def wear!(worn_on: Date.current, outfit: nil, context: nil)
    transaction do
      increment!(:times_worn)
      update!(last_worn_on: worn_on, lifecycle_state: "active") if has_attribute?(:last_worn_on)
      wear_logs.create!(user:, outfit:, worn_on:, context:)
      touch
    end
  end

  def embedding_text
    [ title, category, color, brand, material, season, mood_effect, life_phase, occasion_tags ].compact.join(" ")
  end

  def declutter_score
    DeclutterScore.new(self).score
  end

  def declutter_recommendation
    DeclutterScore.new(self).recommendation
  end

  def duplicate_key
    [ category, color, material, brand ].map { |value| value.to_s.strip.downcase.presence || "unknown" }.join(":")
  end

  def in_declutter_box? = lifecycle_state == "declutter_box"
  def released? = %w[released donated sold recycled].include?(lifecycle_state)
  def sentimental? = lifecycle_state == "sentimental_archive"

  def current_season
    m = Time.current.month
    case m
    when 3..5 then "Spring"
    when 6..8 then "Summer"
    when 9..11 then "Autumn"
    else "Winter"
    end
  end

  def archive_out_of_season!
    return unless season.present? && season != "All-Season" && season != current_season
    update!(lifecycle_state: "seasonal_archive")
  end

  def resurface_seasonal!
    if lifecycle_state == "seasonal_archive" && (season == current_season || season == "All-Season")
      update!(lifecycle_state: "active")
    end
  end

  def extract_dominant_color!
    return unless photos.attached?
    photo = photos.first
    tempfile = nil
    begin
      require "vips"
      tempfile = Tempfile.new([ "item", File.extname(photo.filename.to_s.presence || ".jpg") ])
      tempfile.binmode
      tempfile.write(photo.download)
      tempfile.rewind
      image = Vips::Image.new_from_file(tempfile.path)
      # resize to 1px for approx dominant/average color
      thumb = image.resize(1.0 / [ image.width, image.height ].max.to_f)
      px = thumb.getpoint(0, 0)
      r = px[0].to_i.clamp(0, 255)
      g = px[1].to_i.clamp(0, 255)
      b = px[2].to_i.clamp(0, 255)
      hex = "#%02x%02x%02x" % [ r, g, b ]
      update!(color: hex)
    rescue StandardError => e
      Rails.logger.warn("vips dominant color extract failed for item #{id}: #{e.message}")
    ensure
      tempfile&.close!
    end
  end
end
