# frozen_string_literal: true

# The wearer's own planner. `upcoming` only — a planner that scrolls into
# last month is a history, which is what the timeline page is for.
class PlannedOutfitsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "planned_outfits/planned_row", as: :planned_outfit, wrap_in: :li

  private

  def scope = Current.user.planned_outfits.upcoming.includes(:outfit)
end
