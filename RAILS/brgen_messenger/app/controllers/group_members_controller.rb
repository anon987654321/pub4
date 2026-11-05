# frozen_string_literal: true

# Who is in a group DM. Any member may add; only an op removes someone else.
class GroupMembersController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_user_session
  before_action :set_group

  # The people picker the new-conversation page uses, aimed at this group: the
  # same live search over username and display name, without the people who
  # are already in it. Adding someone took their exact username before, which
  # meant knowing it.
  def new
    members = ConversationParticipant.where(conversation_id: @group.id).select(:user_id)
    scope = User.messageable.unblocked_with(Current.user).where.not(id: members)
    scope = apply_live_search(scope, columns: %w[username display_name], vertical: "people")
    @people = PeoplePicker.rank(scope, Current.user).limit(24)
    finish_live_search(partial: "group_members/people_results")
  end

  def create
    user = member_to_add
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

  # The picker posts an id; a typed username still works without it.
  def member_to_add
    return User.messageable.find_by(id: params[:user_id]) if params[:user_id].present?

    User.messageable.find_by(username: params[:username].to_s.strip.downcase)
  end

  def blocked_either_way?(other)
    return false unless Current.user.respond_to?(:blocking?)

    Current.user.blocking?(other) || (other.respond_to?(:blocking?) && other.blocking?(Current.user))
  end
end
