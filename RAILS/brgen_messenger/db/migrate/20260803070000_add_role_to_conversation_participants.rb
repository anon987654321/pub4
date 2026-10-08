# frozen_string_literal: true

# IRC-style modes for channel rosters: participants are members by default, the
# seeded persona bot is an op (@), and the echo bot is a voice (+). Humans stay
# members. Backfills bots already seated in existing channels using the same rule
# ChannelBot.seat_bots applies to new ones (the persona host is the op, echo the
# voice), so rooms show @/+ prefixes immediately after deploy.
class AddRoleToConversationParticipants < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:conversation_participants, :role)
      add_column :conversation_participants, :role, :string, default: "member", null: false
    end

    say_with_time "backfilling seeded bot roles" do
      execute(<<~SQL)
        UPDATE conversation_participants SET role = 'op'
        WHERE user_id IN (SELECT id FROM users WHERE bot = 1 AND username <> 'echo')
      SQL
      execute(<<~SQL)
        UPDATE conversation_participants SET role = 'voice'
        WHERE user_id IN (SELECT id FROM users WHERE bot = 1 AND username = 'echo')
      SQL
    end
  end

  def down
    remove_column :conversation_participants, :role
  end
end
