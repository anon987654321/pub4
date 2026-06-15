# frozen_string_literal: true

class PortsController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show crossref_cves review]
  before_action :set_port, only: %i[show watch unwatch crossref_cves review]

  def index
    scope = Port.includes(:category)
    scope = apply_live_search(scope, columns: %w[name comment], vertical: "ports", filters: { category_id: params[:category_id] }.compact) if live_search_query.present?
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
    @graph_nodes = [{ id: @port.id, label: @port.name, root: true }] +
      @deps.map { |d| { id: d.depends_on_id, label: d.depends_on.name } }
    @graph_links = @deps.map { |d| { source: @port.id, target: d.depends_on_id } }
    @rdeps = @port.reverse_deps.includes(:category).limit(20)
    @comments = @port.comments.roots.includes(:user, replies: :user)
    @comment = Comment.new
    @advisories = @port.security_advisories.recent
    @maintainer = @port.maintainer.present? ? Maintainer.find_by(name: @port.maintainer) : nil
    @pkg_info = begin
      out, = Open3.capture2e("pkg_info", "-q", @port.name) rescue ["(pkg_info not available in this env)"]
      out.strip
    end
    respond_to_cached_show(@port, only: %i[id name version pkgpath comment maintainer last_updated])
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

  def review
    # MASTER port review: scans Makefile/patches for quality (demo using metadata;
    # real impl would load from ports tree import + Master::Judge::Scan::Scanner)
    issues = []
    issues << "missing HOMEPAGE" if @port.homepage.blank?
    issues << "weak COMMENT" if @port.comment.to_s.length < 20
    notice = issues.any? ? "MASTER review: #{issues.join(', ')}" : "MASTER review: clean (no issues found in demo scan)"
    redirect_to @port, notice: notice
  end

  private

  def set_port
    @port = Port.find_by(pkgpath: params[:id].tr("-", "/")) || Port.find(params[:id])
  end
end
