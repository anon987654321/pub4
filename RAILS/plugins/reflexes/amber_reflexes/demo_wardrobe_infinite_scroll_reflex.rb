# frozen_string_literal: true

# amber's one public catalogue, and the only surface here a crawler sees.
class DemoWardrobeInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "demo_wardrobe/item", as: :item

  private

  def scope = Amber::DemoWardrobe.items.with_photos_for_display.recent
end
