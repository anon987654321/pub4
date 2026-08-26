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
  before_action :require_verified_email, only: :create
  before_action :require_user_session
  before_action :set_conversation

  rate_limit to: 40, within: 3.minutes, only: :create, name: "sustained",
    with: -> { redirect_back fallback_location: root_path, alert: t("flash.messages_rate_limited") }

  def create
    @message = @conversation.messages.build(message_params)
    @message.sender = Current.user

    if @message.save

      @conversation.participants.excluding(Current.user).each do |recipient|
        next if recipient.guest? # guests have no durable push endpoint

        Shared::Pushable.push_to(recipient,
          title: Current.user.display_name,
          body:  push_body_for(@message),
          url:   conversation_path(@conversation)
        )
      end
      respond_to do |format|
        # The corner chat widget and the full channel page post to the same
        # endpoint but own different composers; answering with the page form
        # would replace the widget's compact one with page-sized markup.
        format.turbo_stream { render from_widget? ? :create_widget : :create }
        format.html { redirect_to @conversation }
      end
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

  def push_body_for(message)
    return t("messages.push_body_disappearing") if message.should_expire?

    message.content.to_s.truncate(120)
  end

  def set_conversation
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id])
  end

  def message_params
    # parent_id makes it a reply; duration_seconds is set for a voice note.
    params.require(:message).permit(:content, :message_type, :parent_id, :duration_seconds, :attachment)
  end
end
