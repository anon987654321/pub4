```bash
#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
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
}
```
