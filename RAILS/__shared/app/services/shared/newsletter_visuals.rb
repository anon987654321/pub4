# frozen_string_literal: true

require "date"
require "json"
require "net/http"
require "shared/contracts"
Shared::Contracts.require_contract("studio")
require "rbconfig"
require "tmpdir"
require "fileutils"
require "open-uri"
require "securerandom"
require_relative "artwork_pipeline"

module Shared
  # Newsletter artwork is a first-class editorial layer: generated images are
  # graded and materialized into the app's public tree so an email does not
  # depend on a provider URL surviving after delivery.
  class NewsletterVisuals
    Hero = Data.define(:url, :alt, :caption, :source)
    Artwork = Data.define(:url, :alt, :caption, :source)

    REPLICATE_MODEL = ENV.fetch("NEWSLETTER_REPLICATE_MODEL", "black-forest-labs/flux-2-max")
    POSTPRO_PRESET = ENV.fetch("NEWSLETTER_POSTPRO_PRESET", "magic_hour")
    ARTWORK_COUNT = ENV.fetch("NEWSLETTER_ARTWORK_COUNT", "4").to_i.clamp(0, 6)

    class << self
      def hero_for(city_name:, theme:, seed_attachment: nil, public_base: nil, seed: nil)
        new(public_base:).hero_for(city_name:, theme:, seed_attachment:, seed:)
      end

      def artworks_for(city_name:, themes:, public_base: nil, seed: nil)
        new(public_base:).artworks_for(city_name:, themes:, seed:)
      end
    end

    def initialize(public_base: nil)
      @public_base = public_base
    end

    def hero_for(city_name:, theme:, seed_attachment: nil, seed: nil)
      if seed_attachment&.attached?
        processed = postpro_attachment(seed_attachment)
        return Hero.new(
          url: processed,
          alt: "#{city_name} — #{theme}",
          caption: "Processed with postpro",
          source: :postpro,
        ) if processed
      end

      artwork = replicate_artwork(
        city_name:,
        theme:,
        aspect_ratio: "16:9",
        role: "newsletter hero",
        seed:,
      )
      return nil unless artwork

      Hero.new(**artwork.to_h)
    end

    def artworks_for(city_name:, themes:, seed: nil)
      workers = Array(themes).first(ARTWORK_COUNT).map.with_index do |theme, index|
        Thread.new do
          replicate_artwork(
            city_name:,
            theme:,
            aspect_ratio: "3:2",
            role: "newsletter editorial interlude #{index + 1}",
            seed: seed && Integer(seed) + index,
          )
        rescue StandardError => error
          log("artwork #{index + 1} failed: #{error.message}")
          nil
        end
      end

      workers.filter_map(&:value)
    end

    private

    def postpro_attachment(attachment)
      script = postpro_script
      return nil unless script

      Dir.mktmpdir("newsletter-hero") do |dir|
        ext = File.extname(attachment.filename.to_s).presence || ".jpg"
        input = File.join(dir, "input#{ext}")
        output = File.join(dir, "hero.jpg")

        attachment.download { |chunk| File.open(input, "ab") { |file| file.write(chunk) } }
        ok = system(
          RbConfig.ruby, script,
          "--input", input, "--output", output,
          "--preset", POSTPRO_PRESET,
          out: File::NULL, err: File::NULL,
        )
        return publish_file(output, "postpro") if ok && File.exist?(output)
      end
      nil
    rescue StandardError => error
      log("postpro hero failed: #{error.message}")
      nil
    end

    def replicate_artwork(city_name:, theme:, aspect_ratio:, role:, seed: nil)
      token = ENV["REPLICATE_API_TOKEN"].presence
      return nil if token.blank?
      seed ||= Shared::ArtworkPipeline.seed(
        surface: "newsletter",
        city: city_name,
        brief: "#{role}:#{theme}",
      )

      prompt = <<~PROMPT.squish
        #{role}, #{city_name}, Norway. #{theme}. Refined literary magazine
        art direction, sophisticated editorial illustration or candid fashion
        photography as appropriate, tactile material detail, natural light,
        human scale, local specificity, restrained Nordic palette, quietly witty,
        premium print composition, no text, no logos, no invented monuments,
        no recognizable public figures.
      PROMPT
      output = replicate_predict(token:, prompt:, aspect_ratio:, seed:)
      return nil if output.blank?

      url = materialize_url(output, role, city_name, theme, seed)
      return nil if url.blank?

      Artwork.new(
        url:,
        alt: "#{city_name} — #{theme}",
        caption: "Generated with Replicate for this edition",
        source: :replicate,
      )
    rescue StandardError => error
      log("Replicate artwork failed: #{error.class}: #{error.message}")
      nil
    end

    def replicate_predict(token:, prompt:, aspect_ratio:, seed:)
      uri = URI("https://api.replicate.com/v1/models/#{REPLICATE_MODEL}/predictions")
      payload = {
        input: {
          prompt:,
          aspect_ratio:,
          output_format: "webp",
          output_quality: 90,
          seed:,
        },
      }
      response = replicate_post(uri, token, payload)
      prediction = JSON.parse(response)
      prediction_id = prediction["id"].to_s
      unless prediction_id.match?(/\A[a-zA-Z0-9_-]{1,128}\z/)
        raise "Replicate response has no valid prediction ID"
      end

      result = poll_prediction(prediction_id, token)
      Array(result).grep(%r{\Ahttps://}).first
    end

    def replicate_post(uri, token, body)
      response = Shared::OutboundHttp.request(
        uri,
        method: :post,
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" },
        body: JSON.generate(body)
      )
      raise "Replicate HTTP #{response.code}: #{response.body.to_s[0, 300]}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def poll_prediction(prediction_id, token, attempts: 60)
      uri = URI("https://api.replicate.com/v1/predictions/#{prediction_id}")
      attempts.times do
        response = Shared::OutboundHttp.request(
          uri,
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
        )
        raise "Replicate polling returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        body = JSON.parse(response.body)
        return body["output"] if body["status"] == "succeeded"
        raise "Replicate failed: #{body["error"]}" if body["status"] == "failed"

        sleep 2
      end
      nil
    end

    def materialize_url(url, prefix, city_name, theme, seed)
      dest_dir = File.join(@public_base, "newsletters", Date.current.iso8601)
      FileUtils.mkdir_p(dest_dir)
      filename = "#{prefix.to_s.parameterize}-#{seed}.jpg"
      destination = File.join(dest_dir, filename)

      Shared::ArtworkPipeline.publish_remote(
        url:,
        destination:,
        surface: "newsletter",
        city: city_name,
        brief: theme,
        source: "replicate_newsletter",
      )
      "/newsletters/#{Date.current.iso8601}/#{filename}"
    rescue StandardError => error
      log("materialize artwork failed: #{error.class}: #{error.message}")
      nil
    end

    def publish_file(path, prefix)
      return file_url(path) unless @public_base

      dest_dir = File.join(@public_base, "newsletters", Date.current.iso8601)
      FileUtils.mkdir_p(dest_dir)
      extension = File.extname(path).presence || ".webp"
      dest = File.join(dest_dir, "#{prefix}-#{SecureRandom.hex(6)}#{extension}")
      FileUtils.cp(path, dest)
      "/newsletters/#{Date.current.iso8601}/#{File.basename(dest)}"
    end

    def file_url(path)
      "file://#{path}"
    end

    def postpro_script = ::Contracts::Studio.postpro_script&.to_s

    def log(message)
      Rails.logger.warn("NewsletterVisuals: #{message}") if defined?(Rails)
    end
  end
end
