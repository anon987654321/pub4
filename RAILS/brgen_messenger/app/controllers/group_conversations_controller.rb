# frozen_string_literal: true

# Group DMs. A conversation with a name and more than two people, as opposed to
# a #channel, which is a public room with a slug.
class GroupConversationsController < ApplicationController
  before_action :require_user_session

  def new
    @conversation = Conversation.new
  end

  def create
    users = resolve_usernames(params[:usernames])
    if users.empty?
      redirect_to new_group_path, alert: t("flash.group_needs_people")
      return
    end

    group = Conversation.create_group!(creator: Current.user, name: params[:name], users: users)
    redirect_to conversation_path(group), notice: t("flash.group_created")
  end

  # Renaming only. Disappearing settings stay on ConversationsController#update,
  # which every conversation shares.
  def update
    group = Conversation.for_user(Current.user).find(params[:id])
    return head :forbidden unless group.admin?(Current.user)

    group.update!(name: params.require(:conversation).permit(:name)[:name].to_s.strip.presence)
    redirect_to conversation_path(group), notice: t("flash.group_renamed")
  end

  private

  # Unknown names are dropped rather than failing the whole create: a typo in
  # one of four names should not throw away the other three, and the group page
  # shows who actually joined.
  def resolve_usernames(raw)
    names = raw.to_s.split(",").map { |name| name.strip.downcase }.reject(&:empty?).first(Conversation::MAX_GROUP_PARTICIPANTS)
    return [] if names.empty?

    User.where(username: names).reject { |user| blocked_either_way?(user) }
  end

  def blocked_either_way?(other)
    return false unless Current.user.respond_to?(:blocking?)

    Current.user.blocking?(other) || (other.respond_to?(:blocking?) && other.blocking?(Current.user))
  end
end
