# frozen_string_literal: true

class PortsController < ApplicationController
  allow_unauthenticated_access only: %i[index show crossref_cves]
  before_action :set_port, only: %i[show watch unwatch crossref_cves]

  def index
    scope = Port.includes(:category)
    scope = scope.search(params[:q]) if params[:q].present?
    scope = scope.by_category(params[:category_id]) if params[:category_id].present?
    scope = scope.order(params[:sort] == "updated" ? "last_updated DESC" : :name)

    respond_to do |format|
      format.html do
        @pagy, @ports = pagy(scope)
        @categories = Category.order(:name)
      end
      format.rss do
        @ports = scope.where("last_updated >= ?", 7.days.ago).order(last_updated: :desc).limit(100)
        render layout: false
      end
    end
  end

  def show
    @updates = @port.port_updates.order(committed_at: :desc).limit(10)
    @deps = @port.depends_on.includes(:category)
    @rdeps = @port.reverse_deps.includes(:category).limit(20)
    @comments = @port.comments.roots.includes(:user, replies: :user)
    @comment = Comment.new
    @advisories = @port.security_advisories.recent
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

  def crossref_cves
    NvdCveService.crossref(@port)
    redirect_to @port, notice: "CVE cross-reference complete."
  end

  private

  def set_port
    @port = Port.find_by(pkgpath: params[:id].tr("-", "/")) || Port.find(params[:id])
  end
end
