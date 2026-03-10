```zsh
#!/usr/bin/env zsh
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

setup_messenger_models() {
  log "Setting up Messenger models: Conversation, Message, properly"

  # Generate all required models
  bin/rails generate model Conversation conversation_type:string name:string disappearing_messages:boolean user:references last_read_at:datetime notifications_enabled:boolean
  bin/rails generate model Message conversation:references user:references content:text message_type:string encrypted:boolean expires_at:datetime read_at:datetime
  bin/rails generate model ConversationParticipant conversation:references user:references last_read_at:datetime
  bin/rails generate model TypingIndicator conversation:references user:references expires_at:datetime
  bin/rails generate model MessageAttachment message:references file_name:string file_type:string file_size:integer
  bin/rails generate model MessageReceipt message:references user:references read_at:datetime delivered_at:datetime

  log "Running database migrations..."
  bin/rails db:migrate

  log "Messenger models generated and migrated"
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

  validates :message_id, presence: true
  validates :user_id, presence: true

  scope :read, -> { where.not(read_at: nil) }
  scope :unread, -> { where(read_at: nil) }
  scope :delivered, -> { where.not(delivered_at: nil) }
end
EOF
}

generate_message_attachment_model() {
  log "Configuring MessageAttachment model"

  cat <<'EOF' > app/models/message_attachment.rb
class MessageAttachment < ApplicationRecord
  belongs_to :message

  validates :message_id, presence: true
  validates :file_name, presence: true
  validates :file_type, presence: true
  validates :file_size, numericality: { greater_than_or_equal_to: 0 }
end
EOF
}

main() {
  log "Starting messenger setup..."

  setup_messenger_models
  generate_conversation_model
  generate_message_receipt_model
  generate_message_attachment_model

  log "Messenger setup completed successfully!"
}

main "$@"
```
