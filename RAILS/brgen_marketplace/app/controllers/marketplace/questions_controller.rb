# frozen_string_literal: true

# Asking about a listing in public, and the seller answering there.
class Marketplace::QuestionsController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing

  def create
    question = @listing.questions.new(user: Current.user, body: params.require(:question)[:body])
    if question.ask!
      redirect_to listing_path(@listing), notice: t("flash.marketplace.question_asked")
    else
      redirect_to listing_path(@listing), alert: question.errors.full_messages.first
    end
  end

  # Answering is the seller's, and answerable_by? is the check — not "is this my
  # listing" written out again at the call site.
  def update
    question = @listing.questions.find(params[:id])
    return head :forbidden unless question.answerable_by?(Current.user)

    if question.answer!(params.require(:question)[:answer], by: Current.user)
      redirect_to listing_path(@listing), notice: t("flash.marketplace.question_answered")
    else
      redirect_to listing_path(@listing), alert: question.errors.full_messages.first
    end
  end

  private

  def set_listing = (@listing = find_by_slug_or_id(Marketplace::Listing, params[:listing_id]))
end
