# frozen_string_literal: true

class BlocksController < ApplicationController
  before_action :require_user_session

  def create
    target = User.find(params[:user_id])
    Current.user.block!(target)
    redirect_back fallback_location: main_app.user_path(target), notice: t("block.done", default: "Blocked.")
  end

  def destroy
    # Scoped to Current.user's own blocks — you can only lift a block you placed.
    Current.user.blocks_as_blocker.find_by(blocked_id: params[:user_id])&.destroy
    redirect_back fallback_location: main_app.user_path(params[:user_id]), notice: t("block.undone", default: "Unblocked.")
  end
end
