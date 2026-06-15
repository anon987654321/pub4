# frozen_string_literal: true

class Marketplace::ListingWizardsController < Marketplace::BaseController
  STEPS = %w[category photos details price location review].freeze

  before_action :require_real_user

  def show
    @step = (params[:step] || session[:listing_wizard_step] || STEPS.first)
    @step = STEPS.include?(@step) ? @step : STEPS.first
    session[:listing_wizard_step] = @step
    @draft = session[:listing_wizard_draft] ||= {}
    @listing = Marketplace::Listing.new(@draft.symbolize_keys)
    @categories = Marketplace::Category.roots.includes(:children)
  end

  def update
    draft = (session[:listing_wizard_draft] ||= {})
    draft.merge!(wizard_params)
    session[:listing_wizard_draft] = draft

    current = params[:step].to_s
    next_step = STEPS[(STEPS.index(current) || -1) + 1]

    if next_step.nil?
      listing = Current.user.marketplace_listings.build(draft.symbolize_keys)
      if listing.save
        session.delete(:listing_wizard_draft)
        session.delete(:listing_wizard_step)
        redirect_to marketplace_listing_path(listing), notice: "Listed"
      else
        @step = "review"
        @draft = draft
        @listing = listing
        @categories = Marketplace::Category.all
        render :show, status: :unprocessable_entity
      end
    else
      redirect_to marketplace_listing_wizard_path(step: next_step)
    end
  end

  private

  def wizard_params
    params.fetch(:marketplace_listing, {}).permit(
      :title, :description, :price_cents, :condition, :location, :category_id
    ).to_h.compact_blank
  end
end