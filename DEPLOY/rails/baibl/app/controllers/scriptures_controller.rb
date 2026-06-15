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
    @verses  = @chapter.verses.order(:number).includes(:highlights, :bookmarks, :annotations)
  end

  def search
    query = params[:q].to_s.strip
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    scope = Verse.full_text_search(query).includes(:book, :chapter)
    @pagy, @verses = pagy(scope, items: 20)
    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Shared::SearchAnalytics.log(
      query: query,
      result_count: @verses.size,
      latency_ms: latency_ms,
      vertical: "scriptures",
      actor: Current.user,
      app: "baibl"
    )
    @search_suggestions = @verses.empty? && query.present? ? Shared::SearchSuggestions.for(query, vertical: "scriptures") : []
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
