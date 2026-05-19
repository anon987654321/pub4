# frozen_string_literal: true

class PortsController < ApplicationController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_port, only: %i[show watch unwatch]

  def index
    scope = Port.includes(:category)
    scope = scope.search(params[:q])       if params[:q].present?
    scope = scope.by_category(params[:category_id]) if params[:category_id].present?
    scope = scope.order(params[:sort] == "updated" ? "last_updated DESC" : :name)
    @pagy, @ports = pagy(scope)
    @categories   = Category.order(:name)
  end

  def show
    @updates  = @port.port_updates.order(committed_at: :desc).limit(10)
    @deps     = @port.depends_on.includes(:category)
    @rdeps    = @port.reverse_deps.includes(:category).limit(20)
    @comments = @port.comments.roots.includes(:user, replies: :user)
    @comment  = Comment.new
  end

  def watch
    require_authentication
    @port.watches.find_or_create_by!(user: Current.user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  def unwatch
    require_authentication
    @port.watches.find_by(user: Current.user)&.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  private

  def set_port = @port = Port.find_by!(pkgpath: params[:id].gsub("-", "/")) rescue Port.find(params[:id])
end
