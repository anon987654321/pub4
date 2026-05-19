# frozen_string_literal: true

class NearbyController < ApplicationController
  def index
    lat = Current.user&.latitude
    lng = Current.user&.longitude
    @located = lat.present?
    @nearby = @located ? User.nearby(lat, lng).reject { |u| u == Current.user } : []
  end

  def create
    other = User.find(params[:user_id])
    conversation = Conversation.find_or_create_direct(Current.user, other)
    redirect_to conversation
  end
end
