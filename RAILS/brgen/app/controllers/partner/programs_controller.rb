# frozen_string_literal: true

module Partner
  # Store owners manage partner programs; city creators browse open ones.
  class ProgramsController < ApplicationController
    allow_unauthenticated_access only: %i[index show]
    before_action :require_authentication, except: %i[index show]
    before_action :set_program, only: %i[show edit update]

    def index
      @programs = Partner::Program.open_now.includes(:store).order(created_at: :desc).limit(100)
      @mine = if Current.user.present? && !guest?
                Partner::Membership.where(user: Current.user).includes(:program)
      else
                []
      end
    end

    def show
      @membership = if Current.user.present?
                      Partner::Membership.find_by(program: @program, user: Current.user)
      end
    end

    def new
      @store = Marketplace::Store.find_by!(slug: params[:store_id])
      return unless require_owner_of!(@store)

      @program = Partner::Program.new(
        store: @store,
        city: Current.city_record,
        status: "open",
        commission_model: "cpa_percent",
        commission_rate: 500
      )
    end

    def create
      @store = Marketplace::Store.find_by!(slug: params[:store_id])
      return unless require_owner_of!(@store)

      @program = Partner::Program.new(program_params)
      @program.store = @store
      @program.city ||= Current.city_record

      if @program.save
        redirect_to partner_program_path(@program), notice: t("flash.partner_program_created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      nil unless require_owner_of!(@program.store)
    end

    def update
      return unless require_owner_of!(@program.store)

      if @program.update(program_params)
        redirect_to partner_program_path(@program), notice: t("flash.program_updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_program
      @program = Partner::Program.find(params[:id])
    end

    # owner_id, not owner — the store arrives from a finder with nothing
    # preloaded, and strict_loading_by_default raises on the association read
    # before the comparison runs.
    def require_owner_of!(store)
      return true if store && Current.user && store.owner_id == Current.user.id

      redirect_to partner_programs_path, alert: t("shared.flash.not_authorized")
      false
    end

    def program_params
      params.require(:partner_program).permit(
        :name, :status, :commission_model, :commission_rate,
        :attribution_hours, :hold_days, :auto_approve_partners, :terms
      )
    end
  end
end
