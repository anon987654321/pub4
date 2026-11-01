# frozen_string_literal: true

class ItemsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "items/item", as: :item

  # The band on appended pages too. The first screen interleaves in its own
  # loop, and this reflex renders one partial per row, so without a seam here
  # everything past page one was garments with no band at all. The slot counts
  # from the top of the wardrobe, not the top of the page, so the rhythm does
  # not restart on every scroll.
  def after_row(_record, slot)
    return unless (slot % Shared::AffiliateHelper::FEED_EVERY).zero?

    render(partial: "shared/affiliate_feed_unit", locals: { category: "fashion", in_grid: true })
  end

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
