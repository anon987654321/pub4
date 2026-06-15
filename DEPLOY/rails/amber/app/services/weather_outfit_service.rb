# frozen_string_literal: true

class WeatherOutfitService
  def self.suggest_for(user, event: nil)
    new(user, event: event).suggest
  end

  def initialize(user, event: nil)
    @user = user
    @event = event
  end

  def suggest
    weather = WeatherService.today || { temp: 12, description: "Unknown", summary: "Unknown" }
    weather[:summary] ||= weather[:description]
    season = current_season
    items = @user.items.active_wardrobe.with_attached_photos

    {
      weather: weather,
      season: season,
      event: @event,
      zones: {
        head: pick(items, "Accessories", weather, season),
        top: pick(items, %w[Tops Outerwear], weather, season),
        bottom: pick(items, %w[Bottoms Dresses], weather, season),
        shoes: pick(items, "Shoes", weather, season)
      }
    }
  end

  private

  def current_season
    month = Date.current.month
    case month
    when 3, 4, 5 then "Spring"
    when 6, 7, 8 then "Summer"
    when 9, 10, 11 then "Autumn"
    else "Winter"
    end
  end

  def pick(items, categories, weather, season)
    cats = Array(categories)
    scope = items.where(category: cats)
    scope = scope.where(season: [season, "All-Season", nil]) if scope.column_names.include?("season")
    scope = scope.by_occasion(@event) if @event.present? && scope.respond_to?(:by_occasion)
    scope = scope.never_worn.or(scope.worn_most) if weather[:temp].to_i < 5
    scope.limit(12).to_a
  end
end