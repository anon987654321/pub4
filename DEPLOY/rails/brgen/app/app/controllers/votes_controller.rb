class VotesController < ApplicationController
  before_action :require_authentication

  ALLOWED = %w[Post Comment].freeze

  def create
    votable = find_votable
    vote    = votable.votes.find_or_initialize_by(user: Current.user)

    if vote.persisted? && vote.value == params[:vote][:value].to_i
      vote.destroy
    else
      vote.update!(value: params[:vote][:value])
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def find_votable
    type = params[:votable_type].to_s.classify
    raise ArgumentError unless ALLOWED.include?(type)
    type.constantize.find(params[:votable_id])
  end
end
