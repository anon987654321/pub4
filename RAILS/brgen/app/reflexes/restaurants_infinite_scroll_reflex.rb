# frozen_string_literal: true

class RestaurantsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @restaurants = pagy(restaurants_scope, page: page, request:)
    super
  end

  private

  def page_html
    @restaurants.map do |restaurant|
      render(partial: "takeaway/restaurants/card", locals: { restaurant: })
    end.join
  end

  def restaurants_scope
    scope = Takeaway::Restaurant.active.includes(:user)
    scope = scope.where(cuisine_type: element.dataset["cuisine"]) if element.dataset["cuisine"].present?
    if element.dataset["q"].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
      scope = scope.where(
        "name LIKE ? OR city LIKE ? OR cuisine_type LIKE ? OR description LIKE ?",
        term, term, term, term
      )
    end
    element.dataset["q"].present? ? scope : scope.popular
  end
end
