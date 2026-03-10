```zsh
#!/usr/bin/env zsh
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

setup_messenger_models() {
  log "Setting up Messenger models: Conversation, Message, properly"

  bin/rails generate model Conversation conversation_type:string name:string disappearing_messages:boolean user:references last_read_at:datetime notifications_enabled:boolean
  bin/rails generate model Message conversation:references user:references content:text message_type:string encrypted:boolean expires_at:datetime read_at:datetime
  bin/rails generate model ConversationParticipant conversation:references user:references last_read_at:datetime
  bin/rails generate model TypingIndicator conversation:references user:references expires_at:datetime
  bin/rails generate model MessageAttachment message:references file_name:string file_type:string file_size:integer

  log "Messenger models generated"
}

generate_conversation_model() {
  log "Configuring Conversation model"

  cat <<'EOF' > app/models/conversation.rb
class Conversation < ApplicationRecord
  belongs_to :user
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy
  has_many :typing_indicators, dependent: :destroy

  validates :conversation_type, presence: true, inclusion: { in: %w[direct group] }

  enum conversation_type: {
    direct: "direct",
    group: "group"
  }

  scope :for_user, ->(user) { joins(:conversation_participants).where(conversation_participants: { user_id: user.id }) }

  def unread_count_for(user)
    participant = conversation_participants.find_by(user_id: user.id)
    return messages.count unless participant&.last_read_at
    messages.where('created_at > ?', participant.last_read_at).count
  end
end
EOF
}

generate_message_receipt_model() {
  log "Configuring MessageReceipt model"

  cat <<'EOF' > app/models/message_receipt.rb
class MessageReceipt < ApplicationRecord
  belongs_to :message
  belongs_to :user

  scope :delivered, -> { where.not(delivered_at: nil) }
  scope :read, -> { where.not(read_at: nil) }

  def mark_as_delivered
    update(delivered_at: Time.current)
  end

  def mark_as_read
    update(read_at: Time.current)
  end
end
EOF
}

generate_typing_indicator_model() {
  log "Configuring TypingIndicator model"

  cat <<'EOF' > app/models/typing_indicator.rb
class TypingIndicator < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  validates :expires_at, presence: true

  scope :active, -> { where('expires_at > ?', Time.current) }
end
EOF
}

generate_message_model() {
  log "Configuring Message model"

  cat <<'EOF' > app/models/message.rb
class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user
  has_many :message_receipts, dependent: :destroy
  has_many :attachments, class_name: 'MessageAttachment', dependent: :destroy

  validates :content, presence: true, unless: -> { attachments.any? }
  validates :message_type, presence: true, inclusion: { in: %w[text image video file system] }

  enum message_type: {
    text: "text",
    image: "image",
    video: "video",
    file: "file",
    system: "system"
  }

  after_create_commit :create_receipts

  private

  def create_receipts
    conversation.participants.each do |participant|
      message_receipts.create(user: participant)
    end
  end
end
EOF
}

generate_conversation_participant_model() {
  log "Configuring ConversationParticipant model"

  cat <<'EOF' > app/models/conversation_participant.rb
class ConversationParticipant < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  validates :user_id, uniqueness: { scope: :conversation_id }

  def mark_as_read
    update(last_read_at: Time.current)
  end
end
EOF
}

generate_message_attachment_model() {
  log "Configuring MessageAttachment model"

  cat <<'EOF' > app/models/message_attachment.rb
class MessageAttachment < ApplicationRecord
  belongs_to :message

  validates :file_name, presence: true
  validates :file_size, numericality: { greater_than: 0 }
end
EOF
}

main() {
  setup_messenger_models
  generate_conversation_model
  generate_message_receipt_model
  generate_typing_indicator_model
  generate_message_model
  generate_conversation_participant_model
  generate_message_attachment_model

  log "Running migrations"
  bin/rails db:migrate

  log "Messenger setup complete"
}

main "$@"
```
