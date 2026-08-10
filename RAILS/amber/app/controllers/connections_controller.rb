# frozen_string_literal: true

class ConnectionsController < ApplicationController
  before_action :require_real_user

  def index
    @pagy, @connections = pagy(
      Connection.where(requester: Current.user).or(Connection.where(addressee: Current.user))
                .includes(:requester, :addressee).order(created_at: :desc)
    )
  end

  def create
    addressee = User.find(params[:user_id])
    Current.user.connections_requested.find_or_create_by!(addressee: addressee)
    redirect_to connections_path, notice: "Connection requested"
  end

  def update
    connection = Current.user.connections_received.find(params[:id])
    connection.accept! if params[:accept]
    connection.block! if params[:block]
    redirect_to connections_path
  end
end
