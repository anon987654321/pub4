# frozen_string_literal: true
# Patch: add speak:text SSE event + /chat/speak endpoint

ROUTES = "/home/dev/pub4/MASTER/web/config/routes.rb"
CTRL   = "/home/dev/pub4/MASTER/web/app/controllers/chat_controller.rb"
VIEW   = "/home/dev/pub4/MASTER/web/app/views/chat/index.html.erb"

# 1. routes.rb — add chat/speak route
r = File.read(ROUTES)
unless r.include?("chat/speak")
  r.sub!(
    'post "chat/tts",      to: "chat#tts"',
    "post \"chat/tts\",      to: \"chat#tts\"\n  post \"chat/speak\",    to: \"chat#speak\""
  )
  File.write(ROUTES, r)
  puts "routes: patched"
else
  puts "routes: already patched"
end

# 2. chat_controller.rb — add :speak to CSRF skip + def speak
c = File.read(CTRL)
unless c.include?("chat#speak") || c.include?("def speak")
  c.sub!(
    "skip_before_action :verify_authenticity_token, only: [:message, :tts]",
    "skip_before_action :verify_authenticity_token, only: [:message, :tts, :speak]"
  )
  c.sub!(
    "  def tts",
    "  def speak\n    text = params[:text].to_s.strip\n    return head(:bad_request) if text.empty?\n    container[:bus].publish(\"speak:text\", { text: text })\n    head :ok\n  end\n\n  def tts"
  )
  File.write(CTRL, c)
  puts "controller: patched"
else
  puts "controller: already patched"
end

# 3. index.html.erb — add speak:text handler in EventSource onmessage
v = File.read(VIEW)
unless v.include?("speak:text")
  v.sub!(
    "}else if(t==='scan:complete'){",
    "}else if(t==='speak:text'){\n          speakWithAudio((ev.data||{}).text||'');\n        }else if(t==='scan:complete'){"
  )
  File.write(VIEW, v)
  puts "view: patched"
else
  puts "view: already patched"
end
