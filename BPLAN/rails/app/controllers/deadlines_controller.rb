# frozen_string_literal: true

class DeadlinesController < ApplicationController
  def index
    @deadlines = catalog.deadlines
    @today = funding_generated_date
  end

  def ics
    render plain: catalog.deadlines_ics, content_type: "text/calendar"
  end

  private

  def funding_generated_date
    catalog.funding["generated"].to_s
  end
end