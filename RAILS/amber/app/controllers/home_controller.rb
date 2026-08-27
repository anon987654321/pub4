# frozen_string_literal: true

class HomeController < ApplicationController
  include Shared::MasterGuestHome

  def index
    return render_master_guest_home!(title: "Amber") if params[:master].present? && master_guest_home?

    unless authenticated?
      if Amber::DemoWardrobe.available?
        @demo_items = Amber::DemoWardrobe.preview_items
        @demo_outfits = Amber::DemoWardrobe.preview_outfits
      end
      @pagy, @guest_posts = pagy(Post.public_feed.includes(:outfit, :item, user: :profile))
      @anon_service = Shared::AnonymousPost.new(request: request, user: Current.user)
      return
    end

    items = Current.user.items
    @items_count = items.count
    @joy_count = items.joy.count
    @never_worn_count = items.never_worn.count
    # Utilisation used to count `updated_at`, which is "touched", not "worn":
    # every media job, AI tagging pass and seasonal archive sweep bumped it, so
    # the headline stat on the front page inflated itself. WearLog is the event
    # record and nothing else writes to it; last_worn_on covers wardrobes whose
    # history predates the log.
    window = 30.days.ago.to_date
    logged = WearLog.where(user: Current.user, worn_on: window..).distinct.pluck(:item_id)
    dated = items.where(last_worn_on: window..).pluck(:id)
    @worn_this_month = (logged | dated).size
    @utilization_rate = @items_count > 0 ? (@worn_this_month * 100.0 / @items_count).round : 0
    # `price > 0` named a column that does not exist — Item stores price_cents
    # and `price` is a MoneyInOre reader, so every signed-in dashboard raised
    # SQLite3::SQLException: no such column: price.
    @worst_cpw = items.where("price_cents > 0 AND times_worn > 0")
                             .select(&:cost_per_wear)
                             .sort_by { |i| -i.cost_per_wear }
                             .first(3)
    @aging_unworn = items.aging_unworn.limit(4)
    @recent_items = items.recent.limit(6)
    @planned_this_week = Current.user.planned_outfits.this_week.includes(:outfit)
    @weather = Weather.today
    # Weather is passed in rather than fetched again: StyleAssistant does no
    # network I/O, so the daily suggestion costs one wardrobe read.
    @today_look = StyleAssistant.new(Current.user, weather: @weather).suggest
  end
end
