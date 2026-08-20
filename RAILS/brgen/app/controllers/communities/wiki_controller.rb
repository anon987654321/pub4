# frozen_string_literal: true

# A community's wiki. Moderators write it; whoever can read the community reads
# it — a public community's wiki open to every visitor is a spam surface, and
# the mod queue is the only tool for cleaning one, so the people who can clean it
# are the people who can write it.
class Communities::WikiController < ApplicationController
  include Shared::FindableBySlug

  allow_unauthenticated_access only: %i[index show]
  before_action :set_community
  before_action :require_readable!
  before_action :require_moderator!, only: %i[new create edit update revert]
  before_action :set_page, only: %i[show edit update revert]

  def index
    @pages = @community.wiki_pages.order(:title)
  end

  def show
    @revisions = @page.revisions.includes(:user).limit(20)
    respond_to do |format|
      format.html
      format.md { render markdown: @page }
    end
  end

  def new
    @page = @community.wiki_pages.new
  end

  def create
    @page = @community.wiki_pages.new(page_params.merge(updated_by: Current.user))
    if @page.save
      redirect_to community_wiki_path(@community, @page), notice: t("flash.wiki_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @page.revise!(body: page_params[:body], user: Current.user)
      redirect_to community_wiki_path(@community, @page), notice: t("flash.wiki_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  def revert
    revision = @page.revisions.find(params[:revision_id])
    @page.revert_to!(revision, user: Current.user)
    redirect_to community_wiki_path(@community, @page), notice: t("flash.wiki_reverted")
  end

  private

  def set_community
    @community = find_by_slug_or_id(Community.all, params[:community_id])
  end

  def require_readable!
    head :not_found unless @community.readable_by?(Current.user)
  end

  def require_moderator!
    head :forbidden unless @community.moderator?(Current.user)
  end

  def set_page
    @page = @community.wiki_pages.find_by!(slug: params[:id])
  end

  def page_params
    params.require(:community_wiki_page).permit(:title, :body)
  end
end
