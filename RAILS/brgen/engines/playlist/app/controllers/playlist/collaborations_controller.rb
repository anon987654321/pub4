# frozen_string_literal: true

class Playlist::CollaborationsController < Playlist::BaseController
  before_action :set_target

  def create
    unless authenticated? && owner_or_editor?
      redirect_to(target_path, alert: t("shared.flash.not_authorized")) and return
    end

    username = params[:username].to_s.strip
    target_user = User.find_by(username: username)
    unless target_user
      redirect_to(target_path, alert: t("flash.playlist.user_not_found")) and return
    end

    # Editors used to pass role=owner and then destroy the playlist. The
    # real owner is @target.user_id; this endpoint only mints editor/viewer.
    role = params[:role].to_s
    role = "editor" unless %w[editor viewer].include?(role)
    collab = @target.collaborations.build(user: target_user, role: role)
    if collab.save
      redirect_to(target_path, notice: t("flash.playlist.collaborator_added"))
    else
      redirect_to(target_path, alert: collab.errors.full_messages.to_sentence)
    end
  end

  def destroy
    unless authenticated? && owner_or_editor?
      redirect_to(target_path, alert: t("shared.flash.not_authorized")) and return
    end

    collab = @target.collaborations.find(params[:id])
    collab.destroy
    redirect_to(target_path, notice: t("flash.playlist.collaborator_removed"))
  end

  private

  def set_target
    if params[:set_id]
      @set = Playlist::Set.find(params[:set_id])
      @target = @set
    elsif params[:playlist_id]
      @playlist = find_by_slug_or_id(::Playlist::Playlist, params[:playlist_id])
      @target = @playlist
    else
      redirect_to(playlists_path)
    end
  end

  def target_path
    if @set
      set_path(@set)
    else
      playlist_path(@playlist)
    end
  end

  def owner_or_editor?
    return false unless @target
    owner = Current.user && @target.respond_to?(:user_id) && @target.user_id == Current.user.id
    return true if owner
    collab = @target.collaborations.find_by(user: Current.user)
    collab && %w[owner editor].include?(collab.role)
  end
end
