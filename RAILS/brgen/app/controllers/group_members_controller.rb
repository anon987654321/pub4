# frozen_string_literal: true

# Who is in a group DM. Any member may add; only an op removes someone else.
class GroupMembersController < ApplicationController
  before_action :require_user_session
  before_action :set_group

  def create
    user = User.find_by(username: params[:username].to_s.strip.downcase)
    if user.blank? || blocked_either_way?(user)
      redirect_to conversation_path(@group), alert: t("flash.user_not_found")
      return
    end
    if @group.participants.count >= Conversation::MAX_GROUP_PARTICIPANTS
      redirect_to conversation_path(@group), alert: t("flash.group_full")
      return
    end

    @group.join!(user)
    redirect_to conversation_path(@group), notice: t("flash.group_member_added")
  end

  def destroy
    participant = @group.conversation_participants.find_by!(user_id: params[:id])
    # Leaving is always yours to do; removing someone else is an op's.
    unless participant.user_id == Current.user.id || @group.admin?(Current.user)
      return head :forbidden
    end

    participant.destroy
    @group.promote_longest_standing!
    if participant.user_id == Current.user.id
      redirect_to conversations_path, notice: t("flash.group_left")
    else
      redirect_to conversation_path(@group), notice: t("flash.group_member_removed")
    end
  end

  private

  def set_group
    @group = Conversation.for_user(Current.user).find(params[:group_id])
    head :not_found unless @group.group_dm?
  end

  def blocked_either_way?(other)
    return false unless Current.user.respond_to?(:blocking?)

    Current.user.blocking?(other) || (other.respond_to?(:blocking?) && other.blocking?(Current.user))
  end
end
