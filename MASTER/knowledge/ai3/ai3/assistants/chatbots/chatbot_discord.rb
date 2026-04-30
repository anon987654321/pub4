#!/usr/bin/env ruby
require_relative "chatbot_discord"
module Assistants
  class DiscordAssistant < ChatbotAssistant
    def initialize(openai_api_key)
      super(openai_api_key)
      @browser = Ferrum::Browser.new
    end

    def fetch_user_info(user_id)
      profile_url = "https://discord.com/users/#{user_id}"
      super(user_id, profile_url)
    end

    def send_message(user_id, message, message_type)
      profile_url = "https://discord.com/users/#{user_id}"
      @browser.goto(profile_url)
      css = fetch_dynamic_css_classes(@browser.body, @browser.screenshot(base64: true), "send_message")
      if message_type == :text
        @browser.at_css(css["textarea"]).send_keys(message)
        @browser.at_css(css["submit_button"]).click
      else
        "Media sending not supported."
      end
    end

    def engage_with_new_friends
      @browser.goto("https://discord.com/channels/@me")
      css = fetch_dynamic_css_classes(@browser.body, @browser.screenshot(base64: true), "new_friends")
      @browser.css(css["friend_card"]).each do |friend|
        add_friend(friend[:id])
        engage_with_user(friend[:id], "https://discord.com/users/#{friend[:id]}")
      end
    end

    def fetch_dynamic_css_classes(html, screenshot, action)
      prompt = "Identify CSS classes for #{action} from the following HTML: #{html} and screenshot: #{screenshot}"
      response = @langchain_openai.generate_answer(prompt)
      JSON.parse(response)
    end
  end
end
