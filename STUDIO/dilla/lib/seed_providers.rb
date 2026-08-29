# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"

# External + text seeds for swing, BPM, render RNG — live-coding hooks.
module DillaSeeds
  module_function

  def apply!
    apply_text_seed!
    apply_external_url!
    apply_seismic_stub!
    apply_weather_stub!
  end

  def apply_to_cfg!(cfg)
    apply!
    cfg[:swing] = ENV["SWING"].to_f if ENV["SWING"]
    cfg[:bpm] = ENV["BPM"].to_f if ENV["BPM"]
    cfg
  end

  # SEED_TEXT names a seed by its text, so the same text must name the same seed
  # in every process. Ruby randomises String#hash per process (a security
  # default), so it cannot carry that promise; a SHA-256 digest is stable across
  # runs. SWING and BPM are derived from the same value, so they were drifting too.
  def stable_seed(text) = Digest::SHA256.hexdigest(text.to_s).to_i(16) % (1 << 62)

  def render_seed
    base = ENV["GEN_SEED"]&.to_i
    return base if base&.positive?
    text = ENV["SEED_TEXT"].to_s
    return stable_seed(text) % 1_000_000 if text.length.positive?
    rand(1_000_000)
  end

  def apply_text_seed!
    text = ENV["SEED_TEXT"]
    return unless text && !text.empty?
    h = stable_seed(text)
    ENV["GEN_SEED"] ||= h.to_s
    ENV["SWING"] ||= (52 + (h % 11)).to_s
    ENV["BPM"] ||= (84 + (h % 18)).to_s
  end

  def apply_external_url!
    url = ENV["DILLA_SEED_URL"]
    return unless url && !url.empty?
    data = fetch_json(url)
    return unless data.is_a?(Hash)
    ENV["SWING"] = data["swing"].to_s if data["swing"]
    ENV["BPM"] = data["bpm"].to_s if data["bpm"]
    ENV["GEN_SEED"] = data["seed"].to_s if data["seed"]
    if data["humidity"]
      hum = data["humidity"].to_f
      ENV["SWING"] = (50 + hum * 0.12).round.clamp(52, 62).to_s
    end
    ENV["VINYL"] = (data["vinyl"].to_f * 100).round.to_s if data["vinyl"]
  rescue StandardError => e
    warn "DILLA_SEED_URL failed: #{e.message}" if ENV["DILLA_DEBUG"]
  end

  def apply_seismic_stub!
    return unless ENV["SEISMIC_SEED"] == "1"
    mag = fetch_json("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson")
    return unless mag.is_a?(Hash)
    features = mag["features"] || []
    m = features.first&.dig("properties", "mag") || 2.5
    ENV["SWING"] = (54 + m * 2).round.clamp(52, 62).to_s
    ENV["HARM_VOL"] = (2.2 + m * 0.08).round(2).to_s
  rescue StandardError
    nil
  end

  def apply_weather_stub!
    return unless ENV["WEATHER_SEED"] == "1" && ENV["WEATHER_LAT"] && ENV["WEATHER_LON"]
    lat = ENV["WEATHER_LAT"]
    lon = ENV["WEATHER_LON"]
    data = fetch_json("https://api.open-meteo.com/v1/forecast?latitude=#{lat}&longitude=#{lon}&current=relative_humidity_2m")
    hum = data.dig("current", "relative_humidity_2m") || 50
    ENV["SWING"] = (50 + hum * 0.12).round.clamp(52, 62).to_s
  rescue StandardError
    nil
  end

  def fetch_json(url)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 4, read_timeout: 6) do |http|
      res = http.get(uri.request_uri)
      return nil unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    end
  end

  def drift_sleep(base = 0.5)
    return base if ENV["DRIFT_SLEEP"] == "0"
    jitter = Random.new(Process.pid + Time.now.to_i).rand(-0.12..0.18)
    [base + jitter, 0.05].max
  end
end
