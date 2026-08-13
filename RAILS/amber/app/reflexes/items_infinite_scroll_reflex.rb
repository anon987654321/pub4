# frozen_string_literal: true

class ItemsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "items/item", as: :item

  private

  def scope
    scope = Current.user.items.with_photos_for_display.recent
    scope = scope.merge(Item.for_lifecycle(element.dataset["lifecycle"])) if element.dataset["lifecycle"].present?
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where(
      "title LIKE :q OR brand LIKE :q OR category LIKE :q OR color LIKE :q OR material LIKE :q",
      q: term
    )
  end
end
