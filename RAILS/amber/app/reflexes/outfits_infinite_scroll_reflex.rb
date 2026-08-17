# frozen_string_literal: true

class OutfitsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "outfits/outfit", as: :outfit

  # The band on appended pages too. The first screen interleaves in its own
  # loop, and this reflex renders one partial per row, so without a seam here
  # everything past page one was outfits with no band at all. The slot counts
  # from the top of the gallery, not the top of the page, so the rhythm does
  # not restart on every scroll.
  def after_row(_record, slot)
    return unless (slot % Shared::AffiliateHelper::FEED_EVERY).zero?

    render(partial: "shared/affiliate_feed_unit", locals: { category: "fashion", in_grid: true })
  end

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
