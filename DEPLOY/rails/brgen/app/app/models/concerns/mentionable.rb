module Mentionable
  extend ActiveSupport::Concern

  included do
    after_save :sync_mentions
  end

  private

  def sync_mentions
    usernames = (try(:content).to_s + " " + try(:title).to_s).scan(/@(\w+)/).flatten.uniq
    usernames.each do |uname|
      user = User.find_by(username: uname)
      mentions.find_or_create_by!(mentioned_user: user) if user && user != try(:user)
    end
  end
end
