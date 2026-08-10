# frozen_string_literal: true

class OutfitsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "outfits/outfit", as: :outfit

  private

  def scope
    scope = Current.user.outfits.with_images_for_display.order(created_at: :desc)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope = scope.where(
      "name LIKE :q OR season LIKE :q OR category LIKE :q OR occasion LIKE :q",
      q: term
    )
    item_ids = Current.user.items.where("title LIKE ?", term).pluck(:id)
    scope = scope.joins(:outfit_items).where(outfit_items: { item_id: item_ids }).distinct if item_ids.any?
    scope
  end
end
