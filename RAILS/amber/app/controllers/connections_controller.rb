# frozen_string_literal: true

class ConnectionsController < ApplicationController
  before_action :require_real_user

  def index
    load_connections
  end

  def create
    addressee = User.find(params[:user_id])
    Current.user.connections_requested.find_or_create_by!(addressee: addressee)
    redirect_to connections_path, notice: t("flash.connection_requested")
  end

  def update
    connection = Current.user.connections_received.find(params[:id])
    if params[:accept]
      connection.accept!
      notice = t("flash.connection_accepted")
    elsif params[:block]
      connection.block!
      notice = t("flash.connection_blocked")
    end
    respond_to do |format|
      format.turbo_stream do
        load_connections
        flash.now[:notice] = notice
      end
      format.html { redirect_to connections_path, notice: notice }
    end
  end

  private

  def load_connections
    @pagy, @connections = pagy(
      Connection.where(requester: Current.user).or(Connection.where(addressee: Current.user))
                .includes(requester: :profile, addressee: :profile).order(created_at: :desc)
    )
  end
end
