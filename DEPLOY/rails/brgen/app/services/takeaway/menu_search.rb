# frozen_string_literal: true
# AN623: Menu search

module Takeaway
  class MenuSearch
    def initialize(query:, city:, lat: nil, lng: nil, dietary: [])
      @query = query
      @city = city
      @lat = lat
      @lng = lng
      @dietary = dietary
    end

    def results
      scope = MenuItem.joins(:restaurant).merge(Restaurant.where(city: @city))
      scope = scope.where("menu_items.name LIKE ?", "%#{@query}%") if @query.present?
      @dietary.each { |tag| scope = scope.where("dietary_tags LIKE ?", "%#{tag}%") } if @dietary.any?
      scope.order(Arel.sql("restaurants.rating DESC")).limit(50)
    end
  end
end