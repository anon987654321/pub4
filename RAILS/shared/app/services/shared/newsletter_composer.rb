# frozen_string_literal: true

require "date"

module Shared
  # Seth Godin permission-marketing composer: one idea, personal voice, curated picks.
  class NewsletterComposer
    Edition = Data.define(
      :kind, :app_name, :city_name, :locale, :subject, :preheader, :lede, :sign_off,
      :hero_url, :hero_alt, :hero_caption, :stories, :deals,
      :cta_label, :cta_url, :permission_line, :edition_date
    )

    Story = Data.define(:title, :url, :teaser, :meta, :image_url)
    Deal = Data.define(:title, :url, :description, :price, :currency, :merchant, :image_url)

    MODEL = ENV.fetch("NEWSLETTER_MODEL", ENV.fetch("REWRITE_MODEL", "google/gemini-2.0-flash-001"))

    def self.daily(city_name:, stories:, hero: nil, app_name: "Brgen", locale: "en", cta_url: nil, host: nil)
      new(app_name:, locale:, host:).daily(city_name:, stories:, hero:, cta_url:)
    end

    def self.weekly_deals(city_name:, deals:, hero: nil, app_name: "Brgen", locale: "en", host: nil)
      new(app_name:, locale:, host:).weekly_deals(city_name:, deals:, hero:)
    end

    # host is the city domain this edition is written for, so a letter about
    # Oslo links to oshlo.no. Without it url_for raises "Missing host to link
    # to!" — the rescue below turned that into a nil link for every story and
    # every image, so an edition composed and shipped with nothing to click.
    def initialize(app_name: "Brgen", locale: "en", host: nil)
      @app_name = app_name
      @locale = locale
      @host = host.presence
    end

    def daily(city_name:, stories:, hero: nil, cta_url: nil)
      curated = Array(stories).first(5)
      lede = compose_lede(
        kind: :daily,
        city_name:,
        seed: curated.first,
        fallback: default_daily_lede(city_name)
      )

      Edition.new(
        kind: :daily,
        app_name: @app_name,
        city_name:,
        locale: @locale,
        subject: polish("#{city_name} — #{lede_subject(lede)}"),
        preheader: polish(preheader_for(curated, city_name)),
        lede: polish(lede),
        sign_off: sign_off_for(city_name),
        hero_url: hero&.url,
        hero_alt: hero&.alt || "#{city_name} this week",
        hero_caption: hero&.caption,
        stories: curated.map { |story| story_struct(story) },
        deals: [],
        cta_label: "Open #{@app_name}",
        cta_url: cta_url,
        permission_line: permission_line(city_name),
        edition_date: edition_today
      )
    end

    def weekly_deals(city_name:, deals:, hero: nil)
      curated = Array(deals).first(6)
      lede = compose_lede(
        kind: :weekly_deals,
        city_name:,
        seed: curated.first,
        fallback: default_deals_lede(city_name)
      )

      Edition.new(
        kind: :weekly_deals,
        app_name: @app_name,
        city_name:,
        locale: @locale,
        subject: polish("#{city_name} — picks worth your attention"),
        preheader: polish("Six curated offers for people who live in #{city_name}."),
        lede: polish(lede),
        sign_off: sign_off_for(city_name),
        hero_url: hero&.url,
        hero_alt: hero&.alt || "Curated deals",
        hero_caption: hero&.caption,
        stories: [],
        deals: curated.map { |deal| deal_struct(deal) },
        cta_label: "Browse deals",
        cta_url: nil,
        permission_line: permission_line(city_name),
        edition_date: edition_today
      )
    end

    private

    def edition_today
      return Time.zone.today if defined?(Time) && Time.respond_to?(:zone) && Time.zone

      Date.current
    end

    def read_attr(object, name)
      return object.public_send(name) if object.respond_to?(name)

      nil
    end

    def compose_lede(kind:, city_name:, seed:, fallback:)
      return fallback unless llm_available?

      prompt = <<~PROMPT
        Write the opening paragraph for a permission-marketing email (Seth Godin style).
        One idea. Personal. No hype. No exclamation marks. 2-3 short sentences max.
        City: #{city_name}. Edition: #{kind}. App: #{@app_name}. Language: #{@locale}.
        Seed topic: #{seed_topic(seed)}
        Return plain text only.
      PROMPT

      StrunkWhitePass.call(RubyLLM.chat(model: MODEL).ask(prompt).content.to_s.strip)
    rescue StandardError => error
      Rails.logger.warn("NewsletterComposer lede fallback: #{error.class}") if defined?(Rails)
      fallback
    end

    def llm_available? = defined?(RubyLLM) && ENV["OPENROUTER_API_KEY"].present?

    def seed_topic(seed)
      return "local community" unless seed

      read_attr(seed, :title) || read_attr(seed, :name) || truncate_text(seed.to_s, 120)
    end

    def story_struct(story)
      Story.new(
        title: read_attr(story, :title).to_s,
        url: story_url(story),
        teaser: StrunkWhitePass.call(truncate_text(read_attr(story, :content).to_s, 140)),
        meta: [read_attr(read_attr(story, :community), :name), read_attr(story, :author_name)].compact.join(" · "),
        image_url: story_image_url(story)
      )
    end

    def deal_struct(deal)
      Deal.new(
        title: deal.title.to_s,
        url: deal.click_url.to_s,
        description: StrunkWhitePass.call(truncate_text(deal.description.to_s, 120)),
        price: deal.price.to_s,
        currency: deal.currency.to_s,
        merchant: deal.merchant.to_s,
        image_url: deal.image_url.to_s
      )
    end

    # A newsletter is read outside the app, so every link has to be absolute.
    # url_for raises without a host and there is no request here to infer one
    # from, which is why these take @host rather than relying on a default.
    def url_options
      @host ? { host: @host, protocol: "https" } : {}
    end

    def story_url(story)
      return story if story.is_a?(String)
      return nil unless defined?(Rails) && story.respond_to?(:model_name)

      # polymorphic_url, not url_for: url_for takes one argument, so passing a
      # record and a host raises "wrong number of arguments" — a different
      # ArgumentError from the "Missing host" one, and indistinguishable in a
      # log line that recorded only the class.
      Rails.application.routes.url_helpers.polymorphic_url(story, **url_options)
    rescue StandardError => e
      Rails.logger.warn("newsletter url skipped: #{e.class}: #{e.message}")
      nil
    end

    def story_image_url(story)
      return nil unless story.respond_to?(:image) && story.image.attached?

      variant = story.image.variant(resize_to_limit: [800, 450], format: :webp)
      Rails.application.routes.url_helpers.rails_representation_url(variant, **url_options)
    rescue StandardError => e
      Rails.logger.warn("newsletter url skipped: #{e.class}: #{e.message}")
      nil
    end

    def default_daily_lede(city_name)
      "A short list of what people in #{city_name} are talking about today. " \
        "You asked for this. Here it is."
    end

    def default_deals_lede(city_name)
      "A handful of offers we would actually click ourselves. " \
        "Curated for #{city_name}, not sprayed at everyone on the internet."
    end

    def lede_subject(lede)
      subject = lede.split(/[.!?]/).first.to_s.strip[0, 48]
      subject.empty? ? "today" : subject
    end

    def preheader_for(stories, city_name)
      titles = stories.filter_map { |story| read_attr(story, :title) }.first(2).join(" · ")
      titles.empty? ? "What's moving in #{city_name} today" : titles
    end

    def sign_off_for(city_name) = "— The #{@app_name} editors, #{city_name}"

    def permission_line(city_name)
      "You subscribed because #{city_name} matters to you. " \
        "We send only what we would read ourselves."
    end

    def polish(text) = StrunkWhitePass.call(text.to_s.gsub(/\s+/, " ").strip)

    def truncate_text(text, length)
      string = text.to_s
      return string if string.length <= length

      "#{string[0, length - 1]}…"
    end
  end
end
