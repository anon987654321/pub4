gem "mini_portile2", "~> 2.0.0" # Required in extconf.rbrequire "mini_portile2"

recipe = MiniPortile.new("libiconv", "1.13.1")
recipe.files = ["http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.13.1.tar.gz"]
recipe.cook
recipe.activate
