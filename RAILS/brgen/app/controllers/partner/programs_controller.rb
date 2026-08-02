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
        redirect_to partner_program_path(@program), notice: "Partner program created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      return unless require_owner_of!(@program.store)
    end

    def update
      return unless require_owner_of!(@program.store)

      if @program.update(program_params)
        redirect_to partner_program_path(@program), notice: "Program updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_program
      @program = Partner::Program.find(params[:id])
    end

    def require_owner_of!(store)
      return true if store && Current.user == store.owner

      redirect_to partner_programs_path, alert: "Not allowed."
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

