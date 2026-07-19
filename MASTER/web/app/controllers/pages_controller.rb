# frozen_string_literal: true

class PagesController < ApplicationController
  def radio_bergen
    path = Rails.root.join("..", "..", "web", "radio_bergen.html")
    return head(:not_found) unless File.file?(path)

    send_file path, type: "text/html", disposition: "inline"
  end
end
