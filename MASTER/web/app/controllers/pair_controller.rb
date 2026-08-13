# frozen_string_literal: true

class PairController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create
  skip_before_action :require_container!
  before_action :enforce_web_write_rate_limit, only: :create

  def show
    with_master_fiber(unlocked: cookies[:master_unlocked].to_s == "1") do
      render json: Master::Ground::Pairing.status(cookies[:master_paired].to_s)
    end
  end

  def create
    result = Master::Ground::Pairing.redeem(params[:code].to_s)
    unless result
      render json: { ok: false, error: "invalid or expired code" }, status: :unprocessable_entity
      return
    end

    set_pair_cookie(result[:token])
    render json: { ok: true, profile: "messaging", subject: result[:subject] }
  end
end
