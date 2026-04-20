#!/usr/bin/envzsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

APP_DIR="/home/brgen/app"

# Create models
cat > app/models/conversation.rb << 'RUBY'
# frozen_string_literal: trueclass Conversation < ApplicationRecord
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy
  has_many :typing_indicators, dependent: :destroy

  validates :conversation_type, inclusion: { in: %w[direct group] }

  scope :for_user, ->(u) { joins(:conversation_participants).where(conversation_participants: { user: u }) }

  def self.direct_between(a, b)
    for_user(a).for_user(b).find_by(conversation_type: "direct") ||
      create!(conversation_type: "direct").tap { |c| c.participants.concat([a, b]) }
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user: user)
    return 0 unless participant
    messages.where("created_at > ?", participant.last_read_at || Time.at(0)).count
  end

  def mark_read_for!(user)
    conversation_participants.find_by(user: user)&.update!(last_read_at: Time.now)
  endend
RUBY

cat > app/models/message.rb << 'RUBY'
# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :conversation  belongs_to :sender, class_name: "User", foreign_key: :sender_id
  has_many :message_receipts, dependent: :destroy
  has_one_attached :attachment

  validates :content, presence: true, length: { maximum: 10_000 }
  validates :message_type, inclusion: { in: %w[text image file audio] }

  after_create :deliver_receipts
  after_create :clear_typing_indicators

  scope :recent, -> { order(created_at: :desc) }

  def expired?
    expires_at&.past?
  end

  private

  def deliver_receipts
    conversation.participants.where.not(id: sender_id).each { |u| message_receipts.create!(user: u, delivered_at: Time.now) }
  end

  def clear_typing_indicators
    TypingIndicator.where(conversation: conversation, user: sender).delete_all
  end
end
RUBYcat > app/models/typing_indicator.rb << 'RUBY'
# frozen_string_literal: true

class TypingIndicator < ApplicationRecord
  belongs_to :conversation  belongs_to :user

  scope :active, -> { where("expires_at > ?", Time.now) }

  def self.set!(conversation:, user:)
    find_or_create_by(conversation: conversation, user: user)&.update!(expires_at: 5.seconds.from_now)
  end
end
RUBY

# Create controllers
cat > app/controllers/conversations_controller.rb << 'RUBY'
# frozen_string_literal: true

class ConversationsController < ApplicationController  before_action :authenticate_user!

  def index
    @conversations = Conversation.for_user(current_user)
                                 .includes(:participants, :messages)
                                 .order("messages.created_at DESC")
  end

  def show
    @conversation = Conversation.for_user(current_user).find(params[:id])
    @conversation.mark_read_for!(current_user)
    @messages = @conversation.messages.recent.limit(50).reverse    @message = Message.new
  end  def create
    other = User.find(params[:user_id])
    @conversation = Conversation.find_or_create_direct(current_user, other)
    redirect_to @conversation  end
end
RUBY

cat > app/controllers/messages_controller.rb << 'RUBY'
# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation

  def create
    @message = @conversation.messages.build(message_params)
    @message.sender = current_user    if @message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @conversation }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = Conversation.for_user(current_user).find(params[:conversation_id])
  end

  def message_params
    params.require(:message).permit(:content, :message_type, :attachment)
  end
end
RUBY

cat > app/controllers/typing_indicators_controller.rb << 'RUBY'
# frozen_string_literal: true

class TypingIndicatorsController < ApplicationController
  before_action :authenticate_user!

  def create    conversation = Conversation.for_user(current_user).find(params[:conversation_id])
    TypingIndicator.set!(conversation: conversation, user: current_user)
    head :ok  end
end
RUBY

# Run migrations and finalize
bin/rails db:migrate
echo "==> [messaging] done"