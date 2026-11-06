# frozen_string_literal: true

class PortsController < ApplicationController
  include Shared::LiveSearchable

  helper_method :nvd_operator?

  # Reverse dependencies listed before "show all"; a popular library has hundreds.
  RDEPS_SHOWN = 20

  allow_unauthenticated_access only: %i[index show explore]
  before_action :set_port, only: %i[show explore watch unwatch crossref_cves review]
  # watch/unwatch called require_authentication inside the action body,
  # where its redirect does not halt the action — so the next line ran
  # find_or_create_by!(user: Current.user) for an unauthenticated visitor.
  before_action :require_authentication, only: %i[crossref_cves review watch unwatch]
  before_action :require_nvd_operator, only: :crossref_cves

  def index
    scope = index_scope

    respond_to do |format|
      # The live search asks for a stream; finish_live_search answers it, and an
      # html-only branch here made its second respond_to raise a format mismatch.
      format.any(:html, :turbo_stream) do
        if (exact = exact_pkgpath_port)
          redirect_to exact
          next
        end

        @pagy, @ports = pagy(scope)
        @categories = Category.order(:name)
        @category = Category.find_by(id: params[:category_id]) if params[:category_id].present?
        @catalog_empty = !Port.exists?
        @last_import = ImportRun.recent.first if defined?(ImportRun)
        finish_live_search(partial: "ports/live_search_results")
      end
      # The feed has no chrome, so it can be cached for everyone. The HTML index
      # is root, where sign-in lands, and its nav belongs to one viewer.
      format.rss do
        expires_in 10.minutes, public: true if feed_publicly_cacheable?
        @ports = scope.where("last_updated >= ?", 7.days.ago).order(last_updated: :desc).limit(100)
        render layout: false
      end
    end
  end

  def show
    @watching = authenticated? && @port.watches.exists?(user: Current.user)
    @port.record_activity!("PortViewed", source_vertical: "bsdports") unless passive_request?
    return unless stale?(etag: [ @port.cache_key_with_version, @watching, *Port.related_freshness(@port.id) ])

    @updates = @port.port_updates.order(committed_at: :desc).limit(10)
    @dependencies = @port.dependencies.includes(:depends_on)
    @deps = @port.depends_on.includes(:category)
    load_reverse_deps
    @comments = comment_thread
    @advisories = advisories_worst_first
    @maintainer = @port.maintainer || Maintainer.find_by(name: @port[:maintainer])
    @dependency_tree = Dependency.tree_for(@port)
    @dependency_graph = Dependency.graph_for(@port)
    @explore_summary = Ports::ExploreAssistant.summarize(@port)
    @pkg_info = local_pkg_info
  end

  def watch
    @port.watches.find_or_create_by!(user: Current.user)
    @watching = true
    @port.record_activity!("PortWatched", source_vertical: "bsdports", actor: Current.user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  def unwatch
    # delete_all avoids Reactable association load (no Reaction model on bsdports).
    @port.watches.where(user_id: Current.user.id).delete_all
    @watching = false
    @port.record_activity!("PortUnwatched", source_vertical: "bsdports", actor: Current.user)
    respond_to do |format|
      format.turbo_stream { render :watch }
      format.html { redirect_to @port }
    end
  end

  def explore
    render json: {
      summary: Ports::ExploreAssistant.summarize(@port),
      pkgpath: @port.pkgpath,
      tree: Dependency.tree_for(@port)
    }
  end

  def crossref_cves
    NvdCveCrossrefJob.enqueue_for(port_id: @port.id)
    @port.record_activity!("PortCvesCrossrefQueued", source_vertical: "bsdports")
    redirect_to @port, notice: t("flash.cve_cross_reference_queued")
  end

  def review
    result = Ports::Review.call(port: @port)
    notice = review_notice(result)

    @port.record_activity!(
      "PortReviewed",
      source_vertical: "bsdports",
      metadata: {
        issues: result.issues.map(&:to_s),
        source_status: result.source_status.to_s,
        source_path: result.source_path
      }
    )
    # In place on the page, beside the button; a redirect left the result as
    # a flash at the top, away from where the review was asked for.
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("port-review-result", notice) }
      format.html { redirect_to @port, notice: }
    end
  end

  private

  def issue_labels(issues)
    labels = issues.map(&:to_s).index_with(&:humanize)
    labels.map { |key, fallback| t(key, scope: "flash.review_issue", default: fallback) }.join(", ")
  end

  def review_notice(result)
    issues = result.issues
    return t("flash.review_issues", issues: issue_labels(issues)) if issues.any?

    case result.source_status
    when :unavailable then t("flash.review_source_unavailable")
    when :missing then t("flash.review_source_missing")
    else t("flash.review_clean")
    end
  end

  # Unscoped and in the default language: a shared cache keys on the URL, and
  # the language comes from the session or Accept-Language.
  def feed_publicly_cacheable?
    params[:q].blank? && params[:category_id].blank? && I18n.locale == I18n.default_locale
  end

  def index_scope
    scope = Port.includes(:category)
    if live_search_query.present?
      scope = apply_live_search(scope, columns: %w[name comment description], vertical: "ports")
    end
    scope = scope.by_category(params[:category_id]) if params[:category_id].present?
    scope.ordered_for(live_search_query, params[:sort])
  end

  # A submitted pkgpath names one port; a list of one is a step too many. The
  # live search asks for a stream as the reader types and keeps its list.
  def exact_pkgpath_port
    return if request.format.turbo_stream? || !live_search_query.include?("/")

    matches = Port.where(pkgpath: live_search_query).limit(2).to_a
    matches.first if matches.one?
  end

  # The total is said beside a page's worth, and "show all" lifts the limit.
  def load_reverse_deps
    rdeps = @port.reverse_deps
    rdeps = rdeps.includes(:category).order(:name)
    @rdeps_count = rdeps.count
    @rdeps = params[:rdeps] == "all" ? rdeps : rdeps.limit(RDEPS_SHOWN)
  end

  # The worst first, then the newest within each severity.
  def advisories_worst_first
    advisories = @port.security_advisories
    advisories.order(severity: :desc).recent
  end

  # Each root followed by its replies, in the order the thread reads.
  def comment_thread
    roots = @port.comments.roots
    roots.includes(:user, replies: :user).flat_map { |root| [ root, *root.replies ] }
  end

  # Unknown (nil) where pkg_info cannot be asked: CI and test.
  def local_pkg_info
    return if ENV["CI"] == "1" || Rails.env.test?

    Ports::LocalPackage.info(@port.name)
  end

  def nvd_operator?
    configured_email = ENV["BSDPORTS_ADMIN_EMAIL"].to_s.strip
    return false if configured_email.blank? || Current.user.nil?

    email_matches = Current.user.email_address.to_s.casecmp?(configured_email)
    verified = !Current.user.respond_to?(:email_verified?) || Current.user.email_verified?
    email_matches && verified
  end

  def require_nvd_operator
    head :forbidden unless nvd_operator?
  end

  def set_port
    scope = Port.includes(:category, :platform, :maintainer)
    @port = scope.from_param(params[:id])
  end
end
