# frozen_string_literal: true

class PairController < ApplicationController
  skip_before_action :verify_authenticity_token, only: %i[create issue destroy]
  skip_before_action :require_container!
  before_action :enforce_pair_redeem_rate_limit, only: :create
  before_action :require_authenticated!, only: %i[issue list destroy]

  def show
    with_master_fiber(unlocked: unlocked?) do
      render json: Master::Ground::Pairing.status(cookies[:master_paired].to_s).merge(
        profile: face_profile,
        notice: face_profile == "public" ? Master::Ground::Pairing::REDEEM_NOTICE : nil,
      )
    end
  end

  def create
    result = Master::Ground::Pairing.redeem(params[:code].to_s)
    unless result
      render json: { ok: false, error: "invalid or expired code" }, status: :unprocessable_entity
      return
    end

    set_pair_cookie(result[:token])
    render json: { ok: true, profile: "messaging", subject: result[:subject], notice: Master::Ground::Pairing.redeem_notice(result) }
  end

  def issue
    issued = Master::Ground::Pairing.issue(label: params[:label].to_s)
    render json: issued.merge(ok: true)
  end

  def list
    render json: { rows: Master::Ground::Pairing.list }
  end

  def destroy
    ok = Master::Ground::Pairing.revoke(params[:subject].to_s)
    render json: { ok: }, status: (ok ? :ok : :not_found)
  end
end
