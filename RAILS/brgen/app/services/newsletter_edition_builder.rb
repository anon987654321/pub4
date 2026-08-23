# frozen_string_literal: true

class NewsletterEditionBuilder
  def self.compose_daily!(city: nil)
    new(city:).compose_daily!
  end

  def self.compose_weekly_deals!(city: nil)
    new(city:).compose_weekly_deals!
  end

  def initialize(city: nil)
    @city = city
  end

  def compose_daily!
    cities.flat_map { |city_name| compose_daily_for(city_name) }
  end

  def compose_weekly_deals!
    cities.flat_map { |city_name| compose_weekly_for(city_name) }
  end

  private

  def cities
    return Array(@city) if @city.present?

    slugs = EmailSubscription.marketing_opted_in.distinct.pluck(:city).compact
    slugs.presence || City.limit(12).pluck(:slug).presence || [ "brgen" ]
  end

  def compose_daily_for(city_name)
    city_record = City.find_by(slug: city_name) || City.find_by(domain: "#{city_name}.no")
    posts = fetch_posts(city_record)
    hero = hero_for(city_name:, theme: "morning city letter", seed: posts.first)
    edition = Shared::NewsletterComposer.daily(
      city_name: label_for(city_name, city_record),
      stories: posts,
      hero: hero,
      app_name: "Brgen",
      cta_url: root_url(city_record),
      host: newsletter_host(city_record)
    )
    persist!("daily", city_name, edition)
  end

  def compose_weekly_for(city_name)
    city_record = City.find_by(slug: city_name) || City.find_by(domain: "#{city_name}.no")
    # Prefer real inventory; fall back to any sellable (incl. placeholders) only if empty.
    deals = Shared::Affiliate.deals(limit: 6)
    deals = attach_epi(deals, city: city_name, surface: "newsletter_weekly")
    vouchers = Shared::Tradedoubler.vouchers(limit: 3, site_specific: true)
    hero = hero_for(city_name:, theme: "curated shopping still life", seed: nil)
    edition = Shared::NewsletterComposer.weekly_deals(
      city_name: label_for(city_name, city_record),
      deals: deals,
      hero: hero,
      app_name: "Brgen",
      host: newsletter_host(city_record)
    )
    record = persist!("weekly_deals", city_name, edition)
    merge_vouchers!(record, vouchers) if vouchers.any?
    record
  end

  def attach_epi(deals, city:, surface:)
    epi = Shared::Tradedoubler.epi_for(city: city, surface: surface, edition: Date.current.iso8601)
    Array(deals).map do |deal|
      next deal unless deal.respond_to?(:click_url)

      url = Shared::Tradedoubler.append_epi(deal.click_url, epi: epi)
      if deal.respond_to?(:with)
        deal.with(click_url: url)
      else
        deal
      end
    end
  end

  def merge_vouchers!(record, vouchers)
    existing = Array(record.deals)
    voucher_rows = vouchers.first(2).map do |v|
      {
        "title" => v.title.to_s,
        "url" => v.track_url.to_s,
        "description" => [ v.short_description, v.code.present? ? "Code: #{v.code}" : nil ].compact.join(" — "),
        "price" => v.discount_amount.to_s,
        "currency" => v.currency.to_s,
        "merchant" => v.program_name.to_s,
        "image_url" => nil
      }
    end
    record.update!(deals: existing + voucher_rows)
  end

  def fetch_posts(city_record)
    # with_attached_image, not includes(:image): an attachment is reached
    # through image_attachment and image_blob, and there is no association
    # called :image to preload. This raised AssociationNotFoundError on every
    # run, so no newsletter has ever been composed.
    scope = Post.hot.includes(:user, :community).with_attached_image
    if city_record
      ActsAsTenant.with_tenant(city_record) { scope.limit(6).to_a }
    else
      scope.limit(6).to_a
    end
  end

  def hero_for(city_name:, theme:, seed:)
    attachment = seed&.image if seed&.respond_to?(:image) && seed.image.attached?
    Shared::NewsletterVisuals.hero_for(
      city_name: label_for(city_name, nil),
      theme: theme,
      seed_attachment: attachment,
      public_base: Rails.public_path
    )
  end

  def persist!(kind, city_name, edition)
    NewsletterEdition.find_or_initialize_by(kind:, city: city_name, edition_date: edition.edition_date).tap do |record|
      record.assign_attributes(
        app_name: edition.app_name,
        subject: edition.subject,
        preheader: edition.preheader,
        lede: edition.lede,
        sign_off: edition.sign_off,
        permission_line: edition.permission_line,
        hero_url: edition.hero_url,
        hero_alt: edition.hero_alt,
        hero_caption: edition.hero_caption,
        cta_label: edition.cta_label,
        cta_url: edition.cta_url,
        stories: edition.stories.map(&:to_h),
        deals: edition.deals.map(&:to_h),
        sent_at: nil
      )
      record.save!
    end
  end

  def label_for(city_name, city_record)
    city_record&.name || city_name.to_s.titleize
  end

  # The city's own domain, so a letter about Oslo links to oshlo.no rather than
  # sending every reader to Bergen. APP_HOST is the fallback for a city row with
  # no domain and for the no-city case.
  def newsletter_host(city_record)
    city_record&.domain.presence || ENV.fetch("APP_HOST", "brgen.no")
  end

  def root_url(city_record = nil)
    Rails.application.routes.url_helpers.root_url(host: newsletter_host(city_record), protocol: "https")
  rescue StandardError
    "https://#{newsletter_host(city_record)}"
  end
end
