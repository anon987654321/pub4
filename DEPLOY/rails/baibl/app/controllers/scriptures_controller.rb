# frozen_string_literal: true

class ScripturesController < ApplicationController
  allow_unauthenticated_access only: %i[index book chapter search word_study]

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

  def word_study
    verse    = Verse.includes(:word_studies, cross_references: :target_verse).find(params[:verse_id])
    position = params[:position].to_i
    @study   = verse.word_studies.find_by(position:)
    @xrefs   = verse.cross_references.includes(target_verse: %i[book chapter])
    @verse   = verse
    render partial: "word_study", locals: { study: @study, xrefs: @xrefs, verse: @verse }
  end
end
