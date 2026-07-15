# frozen_string_literal: true

class LegatsController < ApplicationController
  PER_PAGE = 25

  def index
    @track = params[:track].presence
    @show_vx = params[:show_vx].to_s == "1"
    @tracks = catalog.tracks
    @low_priority_count = catalog.low_priority_count
    @legats = catalog.legats_filtered(track: @track, include_low_priority: @show_vx)
    @sendable_count = catalog.legats_sendable.size
    @per_page = PER_PAGE
    @page = [params[:page].to_i, 1].max
    @total_pages = [(@legats.size.to_f / PER_PAGE).ceil, 1].max
    @page = [@page, @total_pages].min
    offset = (@page - 1) * PER_PAGE
    @legats = @legats[offset, PER_PAGE] || []
  end

  def show
    @legat = catalog.legat(params[:id])
    not_found unless @legat

    @body = catalog.legat_html(@legat["id"])
    not_found if @body.blank?

    @sendable = catalog.sendable?(@legat)
    @attachments = catalog.attachment_checklist(@legat)
  end
end