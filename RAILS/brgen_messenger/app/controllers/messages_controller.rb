# frozen_string_literal: true

class MessagesController < ApplicationController
  # One screen of history per request, and the same size as the thread window
  # ConversationsController#show renders, so "load earlier" and first paint
  # agree on what a page of this conversation is. The reply/edit windows are
  # minutes; a history page is 50 lines — a thread that outgrew its window is
  # a transcript to walk, not a wall to load.
  HISTORY_PAGE = 50

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
  # A forward is a message into another thread, and the two limits above cover
  # only :create, so forwarding was an unlimited fan-out.
  rate_limit to: 20, within: 5.minutes, only: :forward, name: "forward",
    by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip },
    with: -> { redirect_back fallback_location: root_path, alert: t("flash.messages_rate_limited") }

  # The page of history above the cursor. `before` is the oldest message the
  # log already holds; the reply carries the next cursor in X-History-Next, or
  # no header when the thread has given up everything above. The body is the
  # message partials alone — the conversation_log controller inserts them at
  # the top of its own list and re-derives grouping and day breaks there, so
  # this action renders no frame, no layout and no chrome. set_conversation
  # scopes through for_user, so a reader reaches only threads they take part in.
  #
  # `after` asks the other way: the lines newer than the newest one the log
  # holds, oldest first, for conversation_catch_up after a dropped socket.
  def index
    return catch_up if params[:after].present?

    page, more = history_page(params[:before].to_i)
    response.set_header("X-History-Next", conversation_messages_path(@conversation, before: page.first.id)) if more
    render_lines(page)
  end

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

    accept_by_answering
    @message = @conversation.messages.build(message_params)
    @message.sender = Current.user

    if @message.save
      notify_recipients(@message)
      render_created
    else
      render_rejected
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

    return refuse_invalid(message) unless message.edit(params.require(:message).permit(:content)[:content])

    # The edit form stood in for the composer; the stream puts the composer back.
    @restore_composer = true
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
    return head(:forbidden) unless message.forwardable?

    target = forward_target
    # The block that holds in create holds here too: a forward is a message into target.
    return refuse_blocked if target.blocked_between?(Current.user)

    copy = message.forward_copy(into: target, sender: Current.user)
    return refuse_invalid(copy) unless copy.save

    redirect_to conversation_path(target), notice: t("flash.message_forwarded")
  end

  # The forward picker: the reader's other threads, built when someone asks to
  # forward one message rather than for every message on every thread page,
  # where each line carried its own select of every other thread.
  def forward_to
    messages = @conversation.messages.visible
    @message = messages.unexpired.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @message.forwardable?

    @forward_targets = forward_targets
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

  # Answering a message request accepts it, as it does anywhere people chat.
  def accept_by_answering
    requests = @conversation.conversation_participants.requests
    requests.find_by(user_id: Current.user.id)&.accept!
  end

  # A socket that was down missed broadcasts Action Cable does not replay. One
  # history page per request; X-Catch-Up-More tells the client to ask again from
  # the last line it got, so a long absence arrives in pages rather than at once.
  def catch_up
    newer = history_scope.where(Message.arel_table[:id].gt(params[:after].to_i))
    lines = newer.order(:id).limit(HISTORY_PAGE + 1).to_a
    return head :no_content if lines.empty?

    response.set_header("X-Catch-Up-More", "1") if lines.size > HISTORY_PAGE
    render_lines(lines.first(HISTORY_PAGE))
  end

  # The newest page above the cursor, oldest first, and whether more is behind it.
  def history_page(before)
    scope = history_scope
    scope = scope.where(Message.arel_table[:id].lt(before)) if before.positive?
    page = scope.recent.limit(HISTORY_PAGE + 1).to_a
    [ page.first(HISTORY_PAGE).reverse, page.size > HISTORY_PAGE ]
  end

  # Message partials alone, rendered for this reader in this request.
  def render_lines(lines)
    render partial: "messages/message", collection: lines
  end

  # The lines a history page may hold, with what each line reads preloaded once
  # for the page, as show does.
  def history_scope
    messages = @conversation.messages
    messages.visible.unexpired
            .includes(:sender, :message_receipts, :link_preview, :reactions, :conversation,
                      parent: :sender).with_attached_attachment
  end

  # Where a forward can go: the reader's other direct threads.
  def forward_targets
    Conversation.for_user(Current.user).where(slug: nil).where.not(id: @conversation.id)
                .includes(:participants)
                .map { |other| [ other.display_name_for(Current.user), other.id ] }
  end

  def render_rejected
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

  def render_created
    # The sender's own copy, reloaded with what the line reads so the partial
    # renders it here as it does in the broadcast job.
    @rendered = Message.strict_loading(false).includes(:sender, :conversation, :link_preview, :reactions,
                                                       :message_receipts).with_attached_attachment
                       .find(@message.id)
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

  # A blank edit or a copy that will not save is the sender's to fix, so they
  # are told why on the thread rather than shown an error page.
  def refuse_invalid(record)
    respond_to do |format|
      format.turbo_stream { head :unprocessable_entity }
      format.html do
        reason = record.errors.full_messages
        redirect_to conversation_path(@conversation), alert: reason.to_sentence
      end
    end
  end

  def forward_target = Conversation.for_user(Current.user).find(params[:target_conversation_id])

  # Web push and, for the iOS shell, APNs: a message is not a Notification row,
  # so NativePushJob never fired for one and a chat never reached a phone. Same
  # words and the same path on both, and one lock-screen thread per conversation.
  def notify_recipients(message)
    payload = { title: Current.user.display_name, body: push_body_for(message), path: conversation_path(@conversation) }
    native = Apns.configured?
    push_recipients.each do |recipient|
      Shared::Pushable.push_to(recipient, title: payload[:title], body: payload[:body], url: payload[:path])
      next unless native

      NativePushJob.perform_later(user_id: recipient.id, thread: "brgen-conversation-#{@conversation.id}", **payload)
    end
  end

  # One query for the memberships and one for who has blocked the sender, rather
  # than a participant load and a block lookup per recipient. A muted thread and
  # a person who blocked the sender get no push; guests and bots have no durable
  # endpoint; a message request waits, silent, until it is accepted.
  def push_recipients
    participants = @conversation.conversation_participants
    recipients = participants.pushable_except(Current.user).includes(:user).map(&:user)
    blockers = Block.where(blocker_id: recipients.map(&:id), blocked_id: Current.user.id).pluck(:blocker_id).to_set
    recipients.reject { |user| user.guest? || user.bot? || blockers.include?(user.id) }
  end

  # Nothing about the words leaves the thread when the thread is meant to be
  # forgotten: the lock screen would otherwise keep what the timer was set to
  # remove. A photo or a voice note says which it is rather than nothing.
  def push_body_for(message)
    return t("messages.push_body_disappearing") if @conversation.ephemeral? || message.should_expire?

    helpers.conversation_preview(@conversation, message, length: 120)
  end

  def set_conversation
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id])
  end

  def message_params
    # parent_id makes it a reply; duration_seconds is set for a voice note.
    params.require(:message).permit(:content, :message_type, :parent_id, :duration_seconds, :attachment, :client_token)
  end
end
