# frozen_string_literal: true

class Weather
  BERGEN_LAT  = 60.39
  BERGEN_LNG  = 5.32
  API_URL     = "https://api.open-meteo.com/v1/forecast"

  # The dashboard asks for this on every authenticated render. Uncached and
  # untimed it was a synchronous round trip to open-meteo in front of amber's
  # front page, on a 1 vCPU box — a slow upstream stalled the page and a hung
  # one held the Falcon fibre until the socket gave up on its own.
  CACHE_KEY = "amber:weather:bergen"
  CACHE_TTL = 15.minutes
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 3

  class << self
    def today
      # Negative caching matters as much as positive: without it an upstream
      # outage means one failed HTTP call per page view, which is the load
      # pattern that turns a degraded dependency into a degraded app. The
      # sentinel distinguishes "fetched, and it failed" from "not fetched".
      cached = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { fetch || :unavailable }
      cached == :unavailable ? nil : cached
    rescue StandardError => e
      Rails.logger.warn("Weather cache: #{e.message}")
      nil
    end

    def fetch
      uri = URI("#{API_URL}?latitude=#{BERGEN_LAT}&longitude=#{BERGEN_LNG}" \
                "&current=temperature_2m,weathercode,windspeed_10m" \
                "&forecast_days=1")
      data = JSON.parse(get(uri))
      current = data["current"]
      {
        temp:        current["temperature_2m"].to_f,
        code:        current["weathercode"].to_i,
        wind:        current["windspeed_10m"].to_f,
        description: decode_weather(current["weathercode"].to_i)
      }
    rescue StandardError => e
      Rails.logger.warn("Weather: #{e.message}")
      nil
    end

    def decode_weather(code)
      case code
      when 0       then "Clear"
      when 1..3    then "Partly cloudy"
      when 45, 48  then "Foggy"
      when 51..67  then "Rainy"
      when 71..77  then "Snowy"
      when 80..82  then "Showers"
      when 95..99  then "Thunderstorm"
      else              "Mixed"
      end
    end

    private

    # Net::HTTP.get takes no timeout options, which is why the old call had
    # none. Going through start/request is the only way to bound it.
    def get(uri)
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT,
                      read_timeout: READ_TIMEOUT) do |http|
        response = http.request(Net::HTTP::Get.new(uri))
        raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end
    end
  end
end
