# frozen_string_literal: true

require "fileutils"
require "i18n"
require "open-uri"

module Shared
  # Deterministic first-party home for generated editorial onboarding art.
  # Generation runs in Solid Queue; rendering never waits for Replicate.
  class OnboardingArtwork
    VERSION = "v1"

    CITY_CUES = {
      "bergen" => "Bryggen wooden waterfront, Vågen harbor, wet cobblestones, fjord light and the seven mountains",
      "oslo" => "Oslo harbor, trams, restrained Nordic architecture, waterfront winter light and ordinary city streets",
      "stavanger" => "white wooden houses, harbor warehouses, North Sea weather and compact pedestrian streets",
      "trondheim" => "Nidelva river, wooden wharves, bicycle culture, low Nordic buildings and cool coastal light",
      "tromso" => "harbor, compact wooden buildings, Arctic weather, mountain silhouettes and long blue-hour light"
    }.freeze

    SURFACE_DIRECTIONS = {
      "brgen" => "observational civic magazine illustration about everyday city life",
      "amber" => "refined fashion editorial illustration about clothes worn in ordinary city life"
    }.freeze

    class << self
      def url(surface:, city:)
        filename = filename_for(surface, city)
        return public_url(filename) if File.file?(output_path(filename))

        enqueue(surface:, city:)
        nil
      end

      def cache_key(surface:, city:)
        "pub4:onboarding-artwork:#{VERSION}:#{sanitize_surface(surface)}:#{slug(city)}"
      end

      def generate(surface:, city:)
        filename = filename_for(surface, city)
        destination = output_path(filename)
        return public_url(filename) if File.file?(destination)

        temporary = nil
        city = sanitize_city(city)
        theme = prompt_for(surface:, city:)

        hero = Shared::NewsletterVisuals.hero_for(city_name: city, theme:)
        source = hero&.url.to_s
        return nil unless source.start_with?("http://", "https://")

        FileUtils.mkdir_p(File.dirname(destination))
        temporary = "#{destination}.tmp-#{Process.pid}-#{Thread.current.object_id}"
        File.binwrite(temporary, URI.open(source, "rb", read_timeout: 30).read)
        File.rename(temporary, destination)
        public_url(filename)
      rescue StandardError => error
        FileUtils.rm_f(temporary) if temporary
        Rails.logger.warn("OnboardingArtwork: #{error.class}: #{error.message}") if defined?(Rails)
        nil
      ensure
        FileUtils.rm_f(temporary) if temporary && File.exist?(temporary)
      end

      private

      def enqueue(surface:, city:)
        token_present = ENV["REPLICATE_API_TOKEN"].present?
        return unless token_present
        return if defined?(Rails) && Rails.env.test?

        key = cache_key(surface:, city:)
        return if Rails.cache.read(key)

        Rails.cache.write(key, true, expires_in: 1.hour)
        Shared::OnboardingArtworkJob.perform_later(surface:, city_name: city)
      rescue StandardError => error
        Rails.cache.delete(key) if key
        Rails.logger.warn("OnboardingArtwork: enqueue failed: #{error.class}: #{error.message}") if defined?(Rails)
      end

      def prompt_for(surface:, city:)
        cues = CITY_CUES[slug(city)].presence ||
          "ordinary streets, local architecture, local weather, public transit and recognizable neighborhood texture"
        direction = SURFACE_DIRECTIONS.fetch(sanitize_surface(surface))
        "#{direction}; unmistakably #{city}, Norway; #{cues}; sophisticated literary-magazine linework, tactile ink and paper texture, restrained natural color, human scale, quietly witty, no text, no logos, no invented monuments, no recognizable public figures"
      end

      def filename_for(surface, city)
        "#{sanitize_surface(surface)}-#{slug(city)}.jpg"
      end

      def output_path(filename)
        Shared::Engine.root.join("public", "generated", "onboarding", VERSION, filename)
      end

      def public_url(filename)
        "/generated/onboarding/#{VERSION}/#{filename}"
      end

      def sanitize_surface(surface)
        surface.to_s.downcase.gsub(/[^a-z0-9_-]/, "")
      end

      def sanitize_city(city)
        city.to_s.gsub(/[^[:alnum:] .'-]/, " ").strip[0, 80]
      end

      def slug(city)
        sanitized = sanitize_city(city)
        transliterated = I18n.transliterate(sanitized)
        transliterated.downcase.gsub(/[^a-z0-9]+/, "-").sub(/\A-/, "").sub(/-\z/, "")[0, 48].presence || "bergen"
      end
    end
  end
end
