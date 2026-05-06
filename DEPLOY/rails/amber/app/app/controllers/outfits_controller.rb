class OutfitsController < ApplicationController
  before_action :require_authentication
  before_action :set_outfit, only: %i[show edit update destroy like]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    @pagy, @outfits = pagy(Current.user.outfits.order(created_at: :desc))
  end

  def show; end

  def new
    @outfit = Current.user.outfits.build
  end

  def create
    @outfit = Current.user.outfits.build(outfit_params)
    @outfit.save ? redirect_to(@outfit, notice: "Outfit created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @outfit.update(outfit_params) ? redirect_to(@outfit, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @outfit.destroy
    redirect_to outfits_path, notice: "Outfit deleted"
  end

  def like
    @outfit.like!
    redirect_to @outfit
  end

  private

  def set_outfit = @outfit = Outfit.find(params[:id])

  def authorize!
    redirect_to(outfits_path, alert: "Unauthorized") unless @outfit.user == Current.user
  end

  def outfit_params
    params.require(:outfit).permit(:name, :description, :category, :season, :occasion)
  end
end
