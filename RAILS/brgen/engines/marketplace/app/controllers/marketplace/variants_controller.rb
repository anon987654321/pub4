# frozen_string_literal: true

# The seller's list of sizes and colours for one listing.
class Marketplace::VariantsController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing
  before_action :require_seller!

  def index
    @variants = @listing.variants.ordered.includes(:options)
    @variant = @listing.variants.new
  end

  def create
    @variant = @listing.variants.new(variant_params)
    options_from(params).each { |name, value| @variant.options.new(name: name, value: value) }
    if @variant.save
      redirect_to listing_variants_path(@listing), notice: t("flash.marketplace.variant_added")
    else
      @variants = @listing.variants.ordered.includes(:options)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    variant = @listing.variants.find(params[:id])
    if variant.destroy
      redirect_to listing_variants_path(@listing), notice: t("flash.marketplace.variant_removed")
    else
      # restrict_with_error: an order is the buyer's receipt, and retiring a size
      # does not own the buyer's half of it.
      redirect_to listing_variants_path(@listing), alert: t("flash.marketplace.variant_has_orders")
    end
  end

  private

  def set_listing = (@listing = find_by_slug_or_id(Marketplace::Listing, params[:listing_id]))

  def require_seller!
    head :forbidden unless Current.user && @listing.user_id == Current.user.id
  end

  def variant_params
    params.require(:variant).permit(:price_cents, :stock, :sku, :position)
  end

  # Two axes in the form, any number in the schema: size and colour is what a
  # shop needs, and the tables do not have to know that.
  def options_from(params)
    raw = params.require(:variant)
    [ [ raw[:option_one_name], raw[:option_one_value] ], [ raw[:option_two_name], raw[:option_two_value] ] ]
      .reject { |name, value| name.blank? || value.blank? }
  end
end
