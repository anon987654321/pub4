# frozen_string_literal: true

class PaymentsController < ApplicationController
  def create
    @plan = catalog.plan(params[:slug])
    not_found unless @plan

    @kind = params[:kind].presence_in(%w[legat in]) || "legat"
    @amount = catalog.pay_amount_for(@plan[:slug], kind: @kind)
    not_found unless @amount.positive?

    @reference = "bplan-#{@plan[:slug]}-#{SecureRandom.hex(4)}"

    redirect_to payment_path(slug: @plan[:slug], kind: @kind, reference: @reference)
  end

  def show
    @plan = catalog.plan(params[:slug])
    not_found unless @plan

    @kind = params[:kind].presence_in(%w[legat in]) || "legat"
    @amount = catalog.pay_amount_for(@plan[:slug], kind: @kind)
    not_found unless @amount.positive?

    @reference = params[:reference].presence || "bplan-#{@plan[:slug]}"
    @vipps = ENV.fetch("BPLAN_VIPPS_NUMBER", ENV.fetch("PUB_VIPPS_NUMBER", nil))
    @email = catalog.applicant["email"] || "bergen@pub.attorney"
  end
end