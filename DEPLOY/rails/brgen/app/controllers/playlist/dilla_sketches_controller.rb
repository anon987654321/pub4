# frozen_string_literal: true

class Playlist::DillaSketchesController < Playlist::BaseController
  before_action :set_parent
  before_action :authorize_editor, only: %i[create update destroy]

  def create
    sketch = @parent.dilla_sketches.build(dilla_sketch_params.merge(user: Current.user))
    if sketch.save
      redirect_to(parent_path, notice: "Dilla sketch saved to collab")
    else
      redirect_to(parent_path, alert: sketch.errors.full_messages.to_sentence)
    end
  end

  def update
    sketch = @parent.dilla_sketches.find(params[:id])
    if sketch.update(dilla_sketch_params)
      redirect_to(parent_path, notice: "Sketch updated")
    else
      redirect_to(parent_path, alert: sketch.errors.full_messages.to_sentence)
    end
  end

  def destroy
    sketch = @parent.dilla_sketches.find(params[:id])
    sketch.destroy
    redirect_to(parent_path, notice: "Sketch removed")
  end

  private

  def set_parent
    if params[:playlist_id]
      @parent = Playlist::Playlist.find(params[:playlist_id])
      @playlist = @parent
    elsif params[:set_id]
      @parent = Playlist::Set.find(params[:set_id])
      @set = @parent
    else
      redirect_to(playlist_playlists_path)
    end
  end

  def parent_path
    if @playlist
      playlist_playlist_path(@playlist)
    else
      playlist_set_path(@set)
    end
  end

  def dilla_sketch_params
    params.require(:playlist_dilla_sketch).permit(:name, :state, :notes).tap do |p|
      # state can come as JSON string from form or already hash
      if p[:state].is_a?(String) && p[:state].present?
        begin
          p[:state] = JSON.parse(p[:state])
        rescue
          p[:state] = {}
        end
      end
    end
  end

  def authorize_editor
    return if Current.user == @parent.user
    collab = @parent.collaborations.find_by(user: Current.user)
    return if collab && %w[owner editor].include?(collab.role)
    redirect_to(parent_path, alert: "Not allowed to edit dilla sketches in this collab")
  end
end
