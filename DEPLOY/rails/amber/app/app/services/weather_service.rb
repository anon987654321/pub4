# frozen_string_literal: true

class WeatherService
  BERGEN_LAT  = 60.39
  BERGEN_LNG  = 5.32
  API_URL     = "https://api.open-meteo.com/v1/forecast"

  def self.today
    uri = URI("#{API_URL}?latitude=#{BERGEN_LAT}&longitude=#{BERGEN_LNG}" \
              "&current=temperature_2m,weathercode,windspeed_10m" \
              "&forecast_days=1")
    data = JSON.parse(Net::HTTP.get(uri))
    current = data["current"]
    {
      temp:        current["temperature_2m"].to_f,
      code:        current["weathercode"].to_i,
      wind:        current["windspeed_10m"].to_f,
      description: decode_weather(current["weathercode"].to_i)
    }
  rescue => e
    Rails.logger.warn("WeatherService: #{e.message}")
    nil
  end

  def self.decode_weather(code)
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
end
