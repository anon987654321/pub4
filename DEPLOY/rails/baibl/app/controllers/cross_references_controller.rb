# frozen_string_literal: true

class CrossReferencesController < ApplicationController
  allow_unauthenticated_access

  def show
    @verse = Verse.includes(cross_references: { target_verse: %i[book chapter] }).find(params[:verse_id])
    @nodes = graph_nodes(@verse)
    @links = graph_links(@verse)
  end

  private

  def graph_nodes(verse)
    nodes = [{ id: verse.id, label: verse.reference, root: true }]
    verse.cross_references.each do |xr|
      tv = xr.target_verse
      nodes << { id: tv.id, label: tv.reference }
    end
    nodes.uniq { |n| n[:id] }
  end

  def graph_links(verse)
    verse.cross_references.map do |xr|
      { source: verse.id, target: xr.target_verse_id, kind: xr.kind }
    end
  end
end