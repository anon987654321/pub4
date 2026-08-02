# frozen_string_literal: true

module Partner
  class MembershipsController < ApplicationController
    before_action :require_authentication

    def create
      program = Partner::Program.find(params[:program_id])
      unless program.open?
        redirect_to partner_program_path(program), alert: "This program is not open." and return
      end

      membership = Partner::Membership.find_or_initialize_by(program: program, user: Current.user)
      if membership.persisted?
        redirect_to partner_program_path(program), notice: "You already joined this program." and return
      end

      membership.status = program.auto_approve_partners? ? "approved" : "pending"
      membership.approved_at = Time.current if membership.status == "approved"
      membership.save!
      redirect_to partner_program_path(program), notice: "Application submitted."
    end

    def show
      @membership = Partner::Membership.find(params[:id])
      unless @membership.user_id == Current.user.id || @membership.program.store.owner_id == Current.user.id
        redirect_to partner_programs_path, alert: "Not allowed." and return
      end

      @clicks = @membership.clicks.order(occurred_at: :desc).limit(50)
      @conversions = @membership.conversions.order(created_at: :desc).limit(50)
    end
  end
end
