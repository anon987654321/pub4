# frozen_string_literal: true

class ConnectionsController < ApplicationController
  before_action :require_real_user

  def index
    load_connections
  end

  def create
    addressee = User.publicly_visible.find(params[:user_id])
    Current.user.connections_requested.find_or_create_by!(addressee: addressee)
    redirect_to connections_path, notice: t("flash.connection_requested")
  end

  def update
    connection = Current.user.connections_received.find(params[:id])
    notice = decide(connection)
    respond_to do |format|
      format.turbo_stream do
        load_connections
        flash.now[:notice] = notice
      end
      format.html { redirect_to connections_path, notice: notice }
    end
  end

  private

  PROFILE_WITH_AVATAR = { profile: { avatar_attachment: :blob } }.freeze

  # Accept, block or decline, and the notice that says which. Declined is gone
  # rather than blocked: a stranger turned down may ask again.
  def decide(connection)
    if params[:accept]
      connection.accept!
      return t("flash.connection_accepted")
    end

    if params[:block]
      connection.block!
      return t("flash.connection_blocked")
    end

    return unless params[:decline] && connection.status == "pending"

    connection.destroy!
    t("flash.connection_declined")
  end

  def load_connections
    @pagy, @connections = pagy(
      Connection.where(requester: Current.user).or(Connection.where(addressee: Current.user))
                .includes(requester: PROFILE_WITH_AVATAR, addressee: PROFILE_WITH_AVATAR).order(created_at: :desc)
    )
  end
end
