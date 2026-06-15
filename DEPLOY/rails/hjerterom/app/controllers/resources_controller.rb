# frozen_string_literal: true

class ResourcesController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]
  before_action :set_resource, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    scope = Resource.includes(:category).verified.order(:title)
    scope = scope.by_type(params[:type]) if params[:type].present?
    scope = apply_live_search(scope, columns: %w[title description resource_type], vertical: "resources") if live_search_query.present?
    @pagy, @resources = pagy(scope)
    @crisis_lines = Crisis.all
    finish_live_search(partial: "resources/live_search_results")
  end

  def show; end

  def new
    @resource = Current.user.resources.build
  end

  def create
    @resource = Current.user.resources.build(resource_params)
    @resource.save ? redirect_to(@resource, notice: "Resource submitted for review") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @resource.update(resource_params) ? redirect_to(@resource, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @resource.destroy
    redirect_to resources_path, notice: "Removed"
  end

  private

  def set_resource  = @resource = Resource.find(params[:id])
  def authorize!    = redirect_to(resources_path, alert: "Unauthorized") unless @resource.user == Current.user

  def resource_params
    params.require(:resource).permit(
      :title, :description, :url, :address, :city, :postal_code,
      :phone, :email, :resource_type, :opening_hours, :category_id
    )
  end
end
