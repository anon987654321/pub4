# frozen_string_literal: true

class TheologicalAssistantController < ApplicationController
  before_action :require_authentication

  def show
    @verse = Verse.find_by(id: params[:verse_id])
    @question = params[:question].to_s
    @answer = TheologicalAssistantService.answer(question: @question, verse: @verse, user: Current.user) if @question.present?
  end

  def create
    @verse = Verse.find_by(id: params[:verse_id])
    @question = params[:question].to_s
    @answer = TheologicalAssistantService.answer(question: @question, verse: @verse, user: Current.user)
    render :show
  end
end