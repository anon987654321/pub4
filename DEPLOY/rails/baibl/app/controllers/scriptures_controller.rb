# frozen_string_literal: true

class ScripturesController < ApplicationController
  include Shared::LiveSearchable

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
    scope = Verse.all.includes(:book, :chapter)
    scope = apply_live_search(scope, columns: %w[content], vertical: "scripture") if live_search_query.present?
    @pagy, @verses = pagy(scope, items: 20)
    finish_live_search(partial: "scriptures/live_search_results")
  end

  def word_study
    verse    = Verse.includes(:word_studies, cross_references: :target_verse).find(params[:verse_id])
    position = params[:position].to_i
    @study   = verse.word_studies.find_by(position:)
    @xrefs   = verse.cross_references.includes(target_verse: %i[book chapter])
    @verse   = verse
    render partial: "word_study", locals: { study: @study, xrefs: @xrefs, verse: @verse }
  end

  # New improved multi-tradition comparisons + visualizations for Bible, Quran, Bhagavad Gita etc.
  # Supports theme keyword or specific refs; leverages cross_references + parallel display + viz.
  def compare
    @traditions = Book::TRADITIONS
    @theme = params[:theme].presence || "creation"
    @results = {}

    # Gather verses by tradition for the theme (simple content/keyword match + cross-refs)
    Book::TRADITIONS.each do |trad|
      books = Book.by_tradition(trad)
      verses = Verse.where(book: books).includes(:book, :chapter, :cross_references)
      matching = verses.where("content LIKE ?", "%#{@theme}%").limit(3)
      if matching.empty?
        # fallback to any + linked via xref
        matching = verses.limit(2)
      end
      @results[trad] = matching
    end

    # Curated cross-tradition links for visualization (thematic/parallel)
    @cross_links = CrossReference.includes(verse: [:book, :chapter], target_verse: [:book, :chapter])
                                 .where(kind: ["thematic", "parallel"]).limit(12)

    if turbo_frame_request?
      render partial: "scriptures/compare_results", locals: { results: @results, cross_links: @cross_links, theme: @theme }
    end
  end
end
