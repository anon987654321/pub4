# frozen_string_literal: true

class RestaurantsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "takeaway/restaurants/card", as: :restaurant

  private

  # Open or closed for the whole page at once, as the first page reads it.
  def after_paginate
    @open_status = Takeaway::OpeningHour.status_for(@records.map(&:id))
  end

  def row_locals(record)
    { restaurant: record, open_status: @open_status[record.id] }
  end

  def scope
    scope = Takeaway::Restaurant.publicly_visible.includes(:user)
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
