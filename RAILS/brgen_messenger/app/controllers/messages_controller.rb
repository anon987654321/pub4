# frozen_string_literal: true

class MessagesController < ApplicationController
  # Burst and sustained, and they only work as two limits because of `name:`.
  # The cache key is ["rate-limit", controller_path, name, by], so unnamed these
  # two shared one counter whenever `by` resolved the same way — which is every
  # request from a signed-out sender, where both fall back to remote_ip. One
  # request then incremented the shared count twice, the 30/minute filter ran
  # first and blocked at 15, and the 40/3-minute limit was unreachable: its TTL
  # was set by whichever call created the key, so it expired after a minute and
  # never accumulated three minutes of anything. See
  # RAILS/test/rate_limit_naming_test.rb.
  rate_limit to: 30, within: 1.minute, only: :create, name: "burst",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  before_action :require_verified_email, only: %i[create forward]
  before_action :require_user_session
  before_action :set_conversation

  rate_limit to: 40, within: 3.minutes, only: :create, name: "sustained",
    with: -> { redirect_back fallback_location: root_path, alert: t("flash.messages_rate_limited") }

  def create
    # A block holds inside an existing thread, not only at the door: the thread
    # stays on both sides' lists, so without this check it was still a channel
    # for the person who had been blocked.
    return refuse_blocked if @conversation.blocked_between?(Current.user)

    # A repeat of an attempt the server already has: answer as the first one was
    # answered and write nothing, so a retry after a lost response is not a
    # second message.
    if (@message = repeat_of_earlier_attempt)
      return render_created
    end

    @message = @conversation.messages.build(message_params)
    @message.sender = Current.user

    if @message.save
      notify_recipients(@message)
      render_created
    else
      respond_to do |format|
        # Keep the dock usable after a validation miss (empty send, etc.).
        format.turbo_stream do
          if from_widget?
            render :create_widget, status: :unprocessable_entity
          else
            head :unprocessable_entity
          end
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # Two copies of one attempt in flight at once: the index kept one, and this
    # request answers with it.
    @message = repeat_of_earlier_attempt or raise
    render_created
  end

  # Editing is bounded to a short window; unsending is not. A message sent to
  # the wrong room, on a chat where people post real addresses, is a safety
  # problem rather than a typo.
  def update
    message = @conversation.messages.find(params[:id])
    return head :forbidden unless message.editable_by?(Current.user)

    message.edit!(params.require(:message).permit(:content)[:content])
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_to conversation_path(@conversation) }
    end
  end

  # Forwarding copies the body into another of the reader's threads. Both ends
  # are scoped to conversations they take part in, so a forward can neither read
  # a thread they are not in nor drop a message into one.
  def forward
    message = @conversation.messages.visible.unexpired.find(params[:id])
    target = Conversation.for_user(Current.user).find(params[:target_conversation_id])
    forwarded = target.messages.create!(
      sender: Current.user, content: message.content, message_type: message.message_type,
      duration_seconds: message.duration_seconds, forwarded_from: message
    )
    # The same blob, not a second upload: a forwarded photo is the photo that
    # was sent, and copying the bytes would double the storage on a 1 GB box.
    forwarded.attachment.attach(message.attachment.blob) if message.attachment.attached?
    redirect_to conversation_path(target), notice: t("flash.message_forwarded")
  end

  def destroy
    message = @conversation.messages.find(params[:id])
    return head :forbidden unless message.deletable_by?(Current.user)

    message.unsend!
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_to conversation_path(@conversation) }
    end
  end

  private

  def from_widget? = params[:origin] == "widget"

  def render_created
    # The sender's own copy, reloaded with what the line reads so the partial
    # renders it here as it does in the broadcast job.
    @rendered = Message.strict_loading(false).includes(:sender, :conversation, :link_preview).find(@message.id)
    respond_to do |format|
      # The corner chat widget and the full channel page post to the same
      # endpoint but own different composers; answering with the page form
      # would replace the widget's compact one with page-sized markup.
      format.turbo_stream { render from_widget? ? :create_widget : :create }
      format.html { redirect_to @conversation }
    end
  end

  def repeat_of_earlier_attempt
    token = message_params[:client_token].presence
    return unless token

    @conversation.messages.find_by(sender_id: Current.user.id, client_token: token)
  end

  def refuse_blocked
    respond_to do |format|
      format.turbo_stream { head :forbidden }
      format.html { redirect_to conversation_path(@conversation), alert: t("flash.messaging_blocked") }
    end
  end

  # One query for the memberships and one for who has blocked the sender, rather
  # than a participant load and a block lookup per recipient. A muted thread and
  # a person who blocked the sender get no push; guests have no durable endpoint.
  def notify_recipients(message)
    memberships = @conversation.conversation_participants
                               .where.not(user_id: Current.user.id).where(muted_at: nil).includes(:user).to_a
    blockers = Block.where(blocker_id: memberships.map(&:user_id), blocked_id: Current.user.id).pluck(:blocker_id).to_set
    memberships.each do |membership|
      recipient = membership.user
      next if recipient.guest? || blockers.include?(recipient.id)

      Shared::Pushable.push_to(recipient,
        title: Current.user.display_name,
        body:  push_body_for(message),
        url:   conversation_path(@conversation)
      )
    end
  end

  # Nothing about the words leaves the thread when the thread is meant to be
  # forgotten: the lock screen would otherwise keep what the timer was set to
  # remove.
  def push_body_for(message)
    return t("messages.push_body_disappearing") if @conversation.ephemeral? || message.should_expire?

    message.content.to_s.truncate(120)
  end

  def set_conversation
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id])
  end

  def message_params
    # parent_id makes it a reply; duration_seconds is set for a voice note.
    params.require(:message).permit(:content, :message_type, :parent_id, :duration_seconds, :attachment, :client_token)
  end
end
