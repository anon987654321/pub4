class ScripturesController < ApplicationController
  allow_unauthenticated_access only: %i[index book chapter search]

  def index
    @books = Book.ordered
    @daily_verse = Verse.order("RANDOM()").limit(1).first
  end

  def book
    @book     = Book.find_by!(abbreviation: params[:abbreviation])
    @chapters = @book.chapters.order(:number)
  end

  def chapter
    @book    = Book.find_by!(abbreviation: params[:book_abbreviation])
    @chapter = @book.chapters.find_by!(number: params[:number])
    @verses  = @chapter.verses.order(:number).includes(:highlights, :bookmarks)
  end

  def search
    @pagy, @verses = pagy(Verse.full_text_search(params[:q]).includes(:book, :chapter), items: 20)
    render :search
  end
end
