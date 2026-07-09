# frozen_string_literal: true

class DocumentsController < ApplicationController
  before_action :require_authentication
  before_action :set_case

  def create
    @document = @case.documents.build(document_params)

    if @document.save
      redirect_to @case, notice: "Document uploaded."
    else
      redirect_to @case, alert: "Upload failed."
    end
  end

  private

  def set_case
    @case = Current.user.cases.find(params[:case_id])
  end

  def document_params
    params.require(:document).permit(:title, :file)
  end
end