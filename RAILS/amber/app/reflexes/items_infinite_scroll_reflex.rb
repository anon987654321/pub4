# frozen_string_literal: true

class ItemsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @items = pagy(items_scope, page: page, request:)
    super
  end

  private

  def page_html
    @items.map { |item| render(partial: "items/item", locals: { item: }) }.join
  end

  def items_scope
    scope = Current.user.items.with_photos_for_display.recent
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where(
      "title LIKE :q OR brand LIKE :q OR category LIKE :q OR color LIKE :q OR material LIKE :q",
      q: term
    )
  end
end
