path = "/home/dev/pub4/.gitignore"
c = File.read(path)
c = c.sub("tmp/\n", "")
c = c.sub("temp/\n", "")
File.write(path, c)
puts "done"
