# frozen_string_literal: true

class AnnotationsController < ApplicationController
  before_action :require_authentication
  before_action :set_verse, only: %i[index create]

  def index
    @annotations = @verse.annotations.includes(:user).recent
    render partial: "annotations/list", locals: { annotations: @annotations, verse: @verse }
  end

  def create
    @annotation = @verse.annotations.build(annotation_params)
    @annotation.user = Current.user
    if @annotation.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to scripture_chapter_path(@verse.book.abbreviation, @verse.chapter.number) + "#v#{@verse.number}", notice: "Annotation saved" }
      end
    else
      render partial: "annotations/form", locals: { annotation: @annotation, verse: @verse }, status: :unprocessable_entity
    end
  end

  def destroy
    @annotation = Current.user.annotations.find(params[:id])
    @annotation.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: scripture_index_path }
    end
  end

  private

  def set_verse
    @verse = Verse.find(params[:verse_id])
  end

  def annotation_params
    params.expect(annotation: %i[body visibility])
  end
end