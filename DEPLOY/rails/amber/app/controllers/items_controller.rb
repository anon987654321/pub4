class ItemsController < ApplicationController
  before_action :require_authentication
  before_action :set_item, only: %i[show edit update destroy spark_joy declutter wear]
  before_action :authorize!, only: %i[edit update destroy spark_joy declutter wear]

  def index
    @pagy, @items = pagy(Current.user.items.recent)
  end

  def show; end

  def new
    @item = Current.user.items.build
  end

  def create
    @item = Current.user.items.build(item_params)
    @item.save ? redirect_to(@item, notice: "Item added") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @item.update(item_params) ? redirect_to(@item, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @item.destroy
    redirect_to items_path, notice: "Removed from wardrobe"
  end

  def spark_joy
    @item.update!(spark_joy: true)
    redirect_to items_path, notice: "This item sparks joy!"
  end

  def declutter
    @item.update!(spark_joy: false)
    redirect_to items_path, notice: "Marked for declutter"
  end

  def wear
    @item.wear!
    redirect_to @item, notice: "Worn today — +1"
  end

  private

  def set_item = @item = Item.find(params[:id])

  def authorize!
    redirect_to(items_path, alert: "Unauthorized") unless @item.user == Current.user
  end

  def item_params
    params.require(:item).permit(
      :title, :category, :color, :size, :material,
      :brand, :price, :times_worn, :purchase_date,
      :mood_effect, :life_phase, :occasion_tags, :season,
      photos: []
    )
  end
end
