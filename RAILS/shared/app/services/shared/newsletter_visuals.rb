# frozen_string_literal: true

require "pub4/deploy_paths"

require "json"
require "net/http"
require "tempfile"
require "rbconfig"
require "fileutils"
require "securerandom"

module Shared
  # Cinematic newsletter hero images via postpro + optional repligen generation.
  class NewsletterVisuals
    Hero = Data.define(:url, :alt, :caption, :source)

    REPLIGEN_MODEL = ENV.fetch("NEWSLETTER_HERO_MODEL", "black-forest-labs/flux-1.1-pro")
    POSTPRO_PRESET = ENV.fetch("NEWSLETTER_POSTPRO_PRESET", "magic_hour")
    POSTPRO_STOCK  = ENV.fetch("NEWSLETTER_POSTPRO_STOCK", "kodak_portra")

    def self.hero_for(city_name:, theme:, seed_attachment: nil, public_base: nil)
      new(public_base:).hero_for(city_name:, theme:, seed_attachment:)
    end

    def initialize(public_base: nil)
      @public_base = public_base
    end

    def hero_for(city_name:, theme:, seed_attachment: nil)
      if seed_attachment&.attached?
        processed = postpro_attachment(seed_attachment)
        return Hero.new(url: processed, alt: "#{city_name} — #{theme}", caption: "Processed with postpro",
source: :postpro) if processed
      end

      generated = repligen_hero(city_name:, theme:)
      return generated if generated

      nil
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
          "--stock", POSTPRO_STOCK, "--preset", POSTPRO_PRESET,
          out: File::NULL, err: File::NULL
        )
        return publish_file(output, "postpro") if ok && File.exist?(output)
      end
      nil
    rescue StandardError => error
      log("postpro hero failed: #{error.message}")
      nil
    end

    def repligen_hero(city_name:, theme:)
      token = ENV["REPLICATE_API_TOKEN"].presence || ENV["REPLIGEN_API_TOKEN"].presence
      return nil if token.blank?

      prompt = "Editorial newsletter hero, #{city_name}, #{theme}, cinematic natural light, " \
               "minimal composition, kodak portra grain, no text, no logos, magazine cover quality"
      output = replicate_predict(token:, prompt:)
      return nil if output.blank?

      Hero.new(url: output, alt: "#{city_name} — #{theme}", caption: "Generated for this edition", source: :repligen)
    rescue StandardError => error
      log("repligen hero failed: #{error.message}")
      nil
    end

    def replicate_predict(token:, prompt:)
      uri = URI("https://api.replicate.com/v1/models/#{REPLIGEN_MODEL}/predictions")
      payload = { input: { prompt:, aspect_ratio: "16:9", output_format: "jpg" } }
      response = replicate_post(uri, token, payload)
      prediction = JSON.parse(response)
      result = poll_prediction(prediction["urls"]["get"], token)
      Array(result).grep(%r{\Ahttps?://}).first
    end

    def replicate_post(uri, token, body)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) { |http| http.request(request) }.body
    end

    def poll_prediction(status_url, token, attempts: 30)
      attempts.times do
        uri = URI(status_url)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{token}"
        body = JSON.parse(Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }.body)
        return body["output"] if body["status"] == "succeeded"
        raise "replicate failed: #{body["error"]}" if body["status"] == "failed"

        sleep 2
      end
      nil
    end

    def publish_file(path, prefix)
      return file_url(path) unless @public_base

      dest_dir = File.join(@public_base, "newsletters", Date.current.iso8601)
      FileUtils.mkdir_p(dest_dir)
      dest = File.join(dest_dir, "#{prefix}-#{SecureRandom.hex(6)}.jpg")
      FileUtils.cp(path, dest)
      "/newsletters/#{Date.current.iso8601}/#{File.basename(dest)}"
    end

    def file_url(path)
      "file://#{path}"
    end

    def postpro_script = Pub4::DeployPaths.postpro_script&.to_s

    def log(message)
      Rails.logger.warn("NewsletterVisuals: #{message}") if defined?(Rails)
    end
  end
end
