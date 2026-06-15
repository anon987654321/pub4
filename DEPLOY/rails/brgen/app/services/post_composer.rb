# frozen_string_literal: true
# AN604: Post composer with slash commands

class PostComposer
  COMMANDS = {
    "/image" => :attach_image,
    "/link" => :attach_link,
    "/poll" => :embed_poll,
    "/code" => :embed_code
  }.freeze

  def initialize(body)
    @body = body.to_s
  end

  def render_html
    html = ApplicationController.helpers.simple_format(@body)
    html = html.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
    html = html.gsub(/^# (.+)$/, '<h2>\1</h2>')
    html
  end

  def apply_commands(post)
    COMMANDS.each do |cmd, method|
      send(method, post) if @body.include?(cmd)
    end
    post
  end

  private

  def attach_image(post); end
  def attach_link(post)
    url = @body[/https?:\/\/\S+/, 0]
    LinkPreviewJob.perform_later(post.id, url) if url
  end
  def embed_poll(post); end
  def embed_code(post); end
end