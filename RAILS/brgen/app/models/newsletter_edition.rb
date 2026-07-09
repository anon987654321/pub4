# frozen_string_literal: true

class NewsletterEdition < ApplicationRecord
  KINDS = %w[daily weekly_deals].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :edition_date, :subject, :lede, presence: true

  scope :for_today, -> { where(edition_date: Date.current) }
  scope :unsent, -> { where(sent_at: nil) }

  def to_edition
    Shared::NewsletterComposer::Edition.new(
      kind: kind.to_sym,
      app_name: app_name,
      city_name: city_label,
      locale: "en",
      subject: subject,
      preheader: preheader,
      lede: lede,
      sign_off: sign_off,
      hero_url: hero_url,
      hero_alt: hero_alt,
      hero_caption: hero_caption,
      stories: Array(stories).map { |row| story_from_json(row) },
      deals: Array(deals).map { |row| deal_from_json(row) },
      cta_label: cta_label,
      cta_url: cta_url,
      permission_line: permission_line,
      edition_date: edition_date
    )
  end

  def city_label = city.presence&.titleize || "Brgen"

  private

  def story_from_json(row)
    Shared::NewsletterComposer::Story.new(
      title: row["title"],
      url: row["url"],
      teaser: row["teaser"],
      meta: row["meta"],
      image_url: row["image_url"]
    )
  end

  def deal_from_json(row)
    Shared::NewsletterComposer::Deal.new(
      title: row["title"],
      url: row["url"],
      description: row["description"],
      price: row["price"],
      currency: row["currency"],
      merchant: row["merchant"],
      image_url: row["image_url"]
    )
  end
end