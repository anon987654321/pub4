# frozen_string_literal: true

# encoding: utf-8

require_relative '../chatbots'
module Assistants
  class SnapChatAssistant < ChatbotAssistant
    def initialize(openai_api_key)
      super(openai_api_key)
      @browser = Ferrum::Browser.new
      puts '🐱‍👤 SnapChatAssistant initialized. Ready to snap like a pro!'
    end
    def fetch_user_info(user_id)
      profile_url = 'https://www.snapchat.com/add/#{user_id}'
      puts '🔍 Fetching user info from #{profile_url}. Time to snoop!'
      super(user_id, profile_url)
    def send_message(user_id, message, message_type)
      puts '🕵️‍♂️ Going to #{profile_url} to send a message. Buckle up!'
      @browser.goto(profile_url)
      css_classes = fetch_dynamic_css_classes(@browser.body, @browser.screenshot(base64: true), 'send_message')
      if message_type == :text
        puts '✍️ Sending text: #{message}'
        @browser.at_css(css_classes['textarea']).send_keys(message)
        @browser.at_css(css_classes['submit_button']).click
      else
        puts '📸 Sending media? Hah! That’s a whole other ball game.'
      end
    def engage_with_new_friends
      @browser.goto('https://www.snapchat.com/add/friends')
      css_classes = fetch_dynamic_css_classes(@browser.body, @browser.screenshot(base64: true), 'new_friends')
      new_friends = @browser.css(css_classes['friend_card'])
      new_friends.each do |friend|
        add_friend(friend[:id])
        engage_with_user(friend[:id], 'https://www.snapchat.com/add/#{friend[:id]}')
    def fetch_dynamic_css_classes(html, screenshot, action)
      puts '🎨 Fetching CSS classes for the #{action} action. It’s like a fashion show for code!'
      prompt = 'Given the following HTML and screenshot, identify the CSS classes used for the #{action} action: #{html} #{screenshot}'
      response = @langchain_openai.generate_answer(prompt)
      JSON.parse(response)
  end
end