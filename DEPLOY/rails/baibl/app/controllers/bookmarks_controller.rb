class BookmarksController < ApplicationController
  before_action :require_authentication

  def index
    @pagy, @bookmarks = pagy(Current.user.bookmarks.includes(verse: [:book, :chapter]))
  end

  def create
    verse = Verse.find(params[:verse_id])
    @bookmark = Current.user.bookmarks.find_or_create_by!(verse: verse)
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end

  def destroy
    @bookmark = Current.user.bookmarks.find(params[:id])
    @bookmark.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to bookmarks_path }
    end
  end
end
