
#!/usr/bin/env zsh

cd "$(dirname "$0")"

# Generate models, controllers, and views for instant messaging
bin/rails generate model Message sender:references recipient:references body:text read:boolean
bin/rails generate controller Messages create show index destroy
echo "resources :messages, only: [:create, :show, :index, :destroy]" >> config/routes.rb

# Update Message model
cat <<EOF > app/models/message.rb
class Message < ApplicationRecord
  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"
  validates :body, presence: true
end
EOF

# Update MessagesController
cat <<EOF > app/controllers/messages_controller.rb
class MessagesController < ApplicationController
  before_action :authenticate_user!

  def index
    @messages = Message.where(sender: current_user).or(Message.where(recipient: current_user))
  end

  def show
    @message = Message.find(params[:id])
    @message.update(read: true) if @message.recipient == current_user
  end

  def create
    @message = Message.new(message_params)
    @message.sender = current_user
    if @message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to messages_path, notice: t("message_sent") }
      end
    else
      render :new
    end
  end

  def destroy
    @message = Message.find(params[:id])
    @message.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to messages_path, notice: t("message_deleted") }
    end
  end

  private

  def message_params
    params.require(:message).permit(:recipient_id, :body)
  end
end
EOF

# Create views for messages
mkdir -p app/views/messages
cat <<EOF > app/views/messages/index.html.erb
<%= tag.h1 t("messages") %>
<%= tag.ul do %>
  <% @messages.each do |message| %>
    <%= tag.li do %>
      <%= link_to message.body.truncate(20), message %>
      <%= message.read ? t("read") : t("unread") %>
    <% end %>
  <% end %>
<% end %>
<%= turbo_stream_from "messages" %>
EOF

cat <<EOF > app/views/messages/show.html.erb
<%= tag.h1 t("message") %>
<p><strong><%= t("from") %>:</strong> <%= @message.sender.email %></p>
<p><strong><%= t("to") %>:</strong> <%= @message.recipient.email %></p>
<p><strong><%= t("body") %>:</strong> <%= @message.body %></p>
<p><strong><%= t("read") %>:</strong> <%= @message.read ? t("yes") : t("no") %></p>
<%= link_to t("back"), messages_path %>
EOF

cat <<EOF > app/views/messages/_form.html.erb
<%= form_with(model: @message, local: true) do |form| %>
  <%= form.label :recipient_id %>
  <%= form.collection_select :recipient_id, User.all, :id, :email, prompt: t("select_recipient") %>
  <%= form.label :body %>
  <%= form.text_area :body %>
  <%= form.submit %>
<% end %>
EOF

cat <<EOF > app/views/messages/new.html.erb
<%= tag.h1 t("new_message") %>
<%= render "form", message: @message %>
<%= link_to t("back"), messages_path %>
EOF

# Turbo Streams for creating and destroying messages
cat <<EOF > app/views/messages/create.turbo_stream.erb
<%= turbo_stream.append "messages" do %>
  <%= render @message %>
<% end %>
EOF

cat <<EOF > app/views/messages/destroy.turbo_stream.erb
<%= turbo_stream.remove dom_id(@message) %>
EOF

bin/rails db:migrate
commit_to_git "Set up instant messaging functionality"
