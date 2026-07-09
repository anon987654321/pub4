# frozen_string_literal: true

class StoresInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @stores = pagy(stores_scope, page: page, request:)
    super
  end

  private

  def page_html
    @stores.map { |store| render(partial: "marketplace/stores/card", locals: { store: }) }.join
  end

  def stores_scope
    scope = Marketplace::Store.active.recent
    scope = scope.by_vertical(element.dataset["vertical"]) if element.dataset["vertical"].present?
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("name LIKE ? OR description LIKE ? OR vertical LIKE ?", term, term, term)
  end
end