# frozen_string_literal: true

class Playlist::DillaSketchesController < Playlist::BaseController
  before_action :set_parent
  before_action :authorize_editor, only: %i[create update destroy render_audio]

  def create
    sketch = @parent.dilla_sketches.build(dilla_sketch_params.merge(user: Current.user, render_status: "idle"))
    if sketch.save
      sketch.enqueue_render!(publish: truthy?(params[:publish])) if truthy?(params[:render_now])
      redirect_to(parent_path, notice: t("dilla.sketch_saved", default: "Dilla sketch saved"))
    else
      redirect_to(parent_path, alert: sketch.errors.full_messages.to_sentence)
    end
  end

  def update
    sketch = @parent.dilla_sketches.find(params[:id])
    if sketch.update(dilla_sketch_params)
      redirect_to(parent_path, notice: t("dilla.sketch_updated", default: "Sketch updated"))
    else
      redirect_to(parent_path, alert: sketch.errors.full_messages.to_sentence)
    end
  end

  def destroy
    sketch = @parent.dilla_sketches.find(params[:id])
    sketch.destroy
    redirect_to(parent_path, notice: t("dilla.sketch_removed", default: "Sketch removed"))
  end

  def render_audio
    sketch = @parent.dilla_sketches.find(params[:id])
    sketch.enqueue_render!(publish: truthy?(params.fetch(:publish, "1")))
    redirect_to(parent_path, notice: t("dilla.render_queued", default: "Dilla render queued — refresh for audio"))
  end

  private

  def set_parent
    if params[:playlist_id]
      @parent = find_by_slug_or_id(::Playlist::Playlist, params[:playlist_id])
      @playlist = @parent
      return
    end
    if params[:set_id]
      @parent = Playlist::Set.find(params[:set_id])
      @set = @parent
      return
    end
    redirect_to(playlists_path)
  end

  def parent_path
    if @playlist
      playlist_path(@playlist)
    else
      set_path(@set)
    end
  end

  def dilla_sketch_params
    params.require(:dilla_sketch).permit(:name, :state, :notes, :style, :bars).tap do |p|
      if p[:state].is_a?(String) && p[:state].present?
        begin
          p[:state] = JSON.parse(p[:state])
        rescue JSON::ParserError
          p[:state] = {}
        end
      end
      p[:state] = {} if p[:state].blank?
    end
  end

  def authorize_editor
    u = Current.user
    # user_id, not user — @parent is found by id with nothing preloaded and
    # strict_loading_by_default raises on the association read.
    owner = (u && u.id == @parent.user_id)
    editor = false
    if (collab = @parent.collaborations.find_by(user: u))
      editor = %w[owner editor].include?(collab.role)
    end
    unless owner || editor
      redirect_to(parent_path, alert: t("dilla.not_allowed", default: "Not allowed to edit dilla sketches in this collab"))
    end
  end

  def truthy?(value)
    %w[1 true yes on].include?(value.to_s.downcase)
  end
end
