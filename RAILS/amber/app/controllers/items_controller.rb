# frozen_string_literal: true

class ItemsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_real_user
  before_action :set_item, only: %i[show edit update destroy spark_joy clear_joy declutter wear archive restore]
  before_action :authorize!, only: %i[edit update destroy spark_joy clear_joy declutter wear archive restore]
  # show was in the set_ list but not the authorize! list, and set_item is an
  # unscoped Item.find — so GET /items/:id returned any user's item (brand,
  # price, purchase date, photos). Gate on viewability rather than ownership so
  # public and follower wardrobes still browse.
  before_action :authorize_view!, only: %i[show]
  # /share is the PWA Web Share Target: the OS posts multipart form data with no
  # CSRF token, so the skip below is required rather than optional. That leaves
  # the action reachable by a cross-site POST, and it creates a record with a
  # caller-supplied title and attached photos. Guests get a soft Current.user
  # here (Shared::Authentication), so without an identity gate the write
  # succeeded for anyone. brgen's posts#share has carried require_real_user for
  # this reason; amber's did not.
  # NO `only:` here, and no second declaration: `before_action :require_real_user`
  # above already covers every action including :share, and Rails DEDUPLICATES
  # callbacks by filter name -- so re-declaring the same filter with
  # `only: [:share]` did not add a second gate, it REPLACED the unrestricted one
  # and narrowed it to :share. Read off the callback chain rather than the
  # source: ItemsController had exactly ONE require_real_user callback and it
  # carried @conditional_key=:only.
  #
  # The effect was the reverse of the intent above -- closing the /share hole
  # opened index, new, create, edit, update and destroy to anyone. Measured on
  # the running app before this fix: anonymous GET /items/new returned 200.
  skip_before_action :verify_authenticity_token, only: [ :share ]

  def index
    scope = Current.user.items.with_photos_for_display
    scope = apply_lifecycle_filter(scope)
    scope = scope.recent
    scope = apply_live_search(scope, columns: %w[title brand category color material], vertical: "wardrobe") if live_search_query.present?
    @pagy, @items = pagy(scope)
    @analytics = WardrobeAnalytics.new(Current.user).summary
    @lifecycle_filter = params[:lifecycle].presence || "active"
    finish_live_search(partial: "items/live_search_results")
  end

  def show
    @item.record_activity!("AmberItemViewed", source_vertical: "amber")
    @ai_available = WardrobeAi.configured?
    # AffiliateLink.new, not @item.affiliate_links.build: build appends the
    # unsaved record to the loaded association, so the view's
    # `@item.affiliate_links.any?` became true for items with none and then
    # built a delete path from link.id == nil, raising "missing required keys:
    # [:id]". Every item without an affiliate link 500'd.
    @affiliate_link = @item.affiliate_links.first || AffiliateLink.new(item: @item)
    @shop_the_look = ShopTheLook.for_item(@item, limit: 6)
  end

  def new
    @item = Current.user.items.build
  end

  def create
    @item = Current.user.items.build(item_params)
    if @item.save
      WardrobeMediaJob.enqueue_for(@item.id) if @item.photos.attached?
      @item.record_activity!("AmberItemCreated", source_vertical: "amber")
      redirect_to(@item, notice: t("flash.item_added"))
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit; end

  def update
    if @item.update(item_params)
      WardrobeMediaJob.enqueue_for(@item.id) if @item.photos.attached?
      @item.record_activity!("AmberItemUpdated", source_vertical: "amber")
      redirect_to(@item, notice: t("flash.updated"))
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @item.record_activity!("AmberItemRemoved", source_vertical: "amber")
    @item.destroy
    redirect_to items_path, notice: t("flash.item_removed")
  end

  def share
    @item = Current.user.items.build(
      title: share_title,
      category: Item::CATEGORIES.first || "Tops",
      price: nil
    )
    attach_shared_photos(@item)

    if @item.save
      @item.record_activity!("AmberItemShared", source_vertical: "amber")
      redirect_to edit_item_path(@item), notice: t("flash.item_shared_into_draft")
    else
      redirect_to new_item_path, alert: t("flash.item_draft_failed")
    end
  end

  def spark_joy
    @item.update!(spark_joy: true)
    @item.record_activity!("AmberItemSparkedJoy", source_vertical: "amber")
    redirect_back fallback_location: @item, notice: t("flash.sparks_joy")
  end

  def clear_joy
    @item.update!(spark_joy: false)
    @item.record_activity!("AmberItemDecluttered", source_vertical: "amber")
    redirect_back fallback_location: @item, notice: t("flash.no_spark_joy")
  end

  def declutter
    @item.update!(spark_joy: false)
    @item.record_activity!("AmberItemDecluttered", source_vertical: "amber")
    redirect_to review_declutter_path(@item), notice: t("flash.marked_for_declutter")
  end

  def archive
    @item.update!(lifecycle_state: "sentimental_archive")
    # NN/g #3 user control: one-step undo via flash restore CTA
    flash[:undo] = {
      "path" => restore_item_path(@item),
      "method" => "post",
      "label" => I18n.t("items.undo_restore"),
    }
    redirect_to @item, notice: I18n.t("items.archived_notice")
  end

  def restore
    @item.update!(lifecycle_state: "active")
    redirect_to @item, notice: I18n.t("items.restored_notice")
  end

  def wear
    @item.wear!
    @item.record_activity!("AmberItemWorn", source_vertical: "amber")
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @item, notice: t("flash.worn_today") }
    end
  end

  def archive_seasonal
    Current.user.items.active_wardrobe.find_each(&:archive_out_of_season!)
    redirect_to items_path, notice: t("flash.out_of_season_archived")
  end

  def resurface_seasonal
    Current.user.items.seasonal_archived.find_each(&:resurface_seasonal!)
    redirect_to items_path, notice: t("flash.seasonal_resurfaced")
  end

  def shopping_list
    service = WardrobeGap.new(Current.user)
    service.create_recommendations!
    @gaps = service.gaps
    @recommendations = Current.user.recommendations.where(kind: "purchase_gap").recent
    # "Allows you to include your own affiliate products as well" was only ever
    # reachable one garment at a time from items#show; there was no view of the
    # links you had already added.
    @affiliate_links = AffiliateLink.joins(:item).where(items: { user_id: Current.user.id })
                                    .includes(:item).order(:merchant)
    # The other half of shopping smarter: what you already own too much of.
    @duplicate_groups = DuplicateDetector.new(Current.user).ranked_groups.first(3)
    @feed_reason = ShopTheLook.remote_unavailable_reason
  end

  private

  # privacy_setting is preloaded because authorize_view! consults it via
  # WardrobeVisibilityPolicy; User is strict_loading, so a lazy load raises.
  # photos + variant_records avoid N+1 when show renders each photo srcset.
  def set_item
    @item = Item.includes(
      :affiliate_links,
      { photos_attachments: { blob: :variant_records } },
      user: :privacy_setting
    ).find(params[:id])
  end

  def authorize!
    redirect_to(items_path, alert: t("shared.flash.not_authorized")) unless @item.user_id == Current.user&.id
  end

  def authorize_view!
    return if WardrobeVisibilityPolicy.new(viewer: Current.user, owner: @item.user).can_view_wardrobe?

    redirect_to(items_path, alert: t("shared.flash.not_authorized"))
  end

  def apply_lifecycle_filter(scope)
    scope.merge(Item.for_lifecycle(params[:lifecycle]))
  end

  def item_params
    params.require(:item).permit(
      :title, :category, :color, :size, :material,
      :brand, :price, :times_worn, :purchase_date,
      :mood_effect, :life_phase, :occasion_tags, :season,
      photos: []
    )
  end

  def share_title
    params[:title].presence || params[:text].presence || params[:url].presence || "Shared item"
  end

  def attach_shared_photos(item)
    Array.wrap(params[:files] || params[:file] || params[:photos]).compact.each do |file|
      item.photos.attach(file)
    end
  end
end
