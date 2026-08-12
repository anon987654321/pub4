# frozen_string_literal: true

class PortsController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show explore]
  before_action :set_port, only: %i[show explore watch unwatch crossref_cves review]
  before_action :require_authentication, only: %i[crossref_cves review]

  def index
    expires_in 10.minutes, public: true if params[:q].blank? && params[:category_id].blank?

    scope = Port.includes(:category)
    scope = apply_live_search(scope, columns: %w[name comment description], vertical: "ports") if live_search_query.present?
    scope = scope.by_category(params[:category_id]) if params[:category_id].present?
    scope = scope.order(params[:sort] == "updated" ? "last_updated DESC" : :name)

    respond_to do |format|
      format.html do
        @pagy, @ports = pagy(scope)
        @categories = Category.order(:name)
        @catalog_empty = !Port.exists?
        @last_import = ImportRun.recent.first if defined?(ImportRun)
        finish_live_search(partial: "ports/live_search_results")
      end
      format.rss do
        @ports = scope.where("last_updated >= ?", 7.days.ago).order(last_updated: :desc).limit(100)
        render layout: false
      end
    end
  end

  def show
    fresh_when(@port, public: true)

    @updates = @port.port_updates.order(committed_at: :desc).limit(10)
    @dependencies = @port.dependencies.includes(:depends_on)
    @deps = @port.depends_on.includes(:category)
    @rdeps = @port.reverse_deps.includes(:category).limit(20)
    @comments = @port.comments.roots.includes(:user, replies: :user)
    @comment = Comment.new
    @watching = authenticated? && @port.watches.exists?(user: Current.user)
    @advisories = @port.security_advisories.recent
    @maintainer = @port.maintainer || Maintainer.find_by(name: @port[:maintainer])
    @dependency_tree = Dependency.tree_for(@port)
    @explore_summary = Ports::ExploreAssistant.summarize(@port)
    @pkg_info = if ENV["CI"] == "1" || Rails.env.test?
      "(pkg_info skipped in CI)"
    else
      begin
        out, = Open3.capture2e("pkg_info", "-q", @port.name)
        out.strip
      rescue StandardError
        "(pkg_info not available in this env)"
      end
    end
    @port.record_activity!("PortViewed", source_vertical: "bsdports")
  end

  def watch
    require_authentication
    @port.watches.find_or_create_by!(user: Current.user)
    @watching = true
    @port.record_activity!("PortWatched", source_vertical: "bsdports", actor: Current.user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  def unwatch
    require_authentication
    # delete_all avoids Reactable association load (no Reaction model on bsdports).
    @port.watches.where(user_id: Current.user.id).delete_all
    @watching = false
    @port.record_activity!("PortUnwatched", source_vertical: "bsdports", actor: Current.user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  def explore
    render json: {
      summary: Ports::ExploreAssistant.summarize(@port),
      pkgpath: @port.pkgpath,
      tree: Dependency.tree_for(@port),
    }
  end

  def crossref_cves
    NvdCve.crossref(@port)
    @port.record_activity!("PortCvesCrossreferenced", source_vertical: "bsdports")
    redirect_to @port, notice: t("flash.cve_cross_reference_complete")
  end

  def review
    # MASTER port review: scans Makefile/patches for quality (demo using metadata;
    # real impl would load from ports tree import + Master::Judge::Scan::Scanner)
    issues = []
    issues << "missing HOMEPAGE" if @port.homepage.blank?
    issues << "weak COMMENT" if @port.comment.to_s.length < 20
    notice = issues.any? ? "MASTER review: #{issues.join(', ')}" : "MASTER review: clean (no issues found in demo scan)"
    @port.record_activity!("PortReviewed", source_vertical: "bsdports", metadata: { issues: issues })
    redirect_to @port, notice: notice
  end

  private

  def set_port
    scope = Port.includes(:category, :platform, :maintainer)
    @port = scope.find_by(pkgpath: params[:id].to_s.tr("-", "/")) || scope.find(params[:id])
  end
end
