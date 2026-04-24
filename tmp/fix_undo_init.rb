# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"
content = File.read(File.join(BASE, "lib/master.rb"), encoding: "utf-8")
content.sub!("Undo.new(session:, event_bus: bus)", "Undo.new(session:, event_bus: bus, root: root)")
File.write(File.join(BASE, "lib/master.rb"), content)
puts "fixed"
