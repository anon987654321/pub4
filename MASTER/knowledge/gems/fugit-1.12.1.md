require 'fugit'

Fugit.parse('0 0 1 Jan *').class          # => ::Fugit::Cron
Fugit.parse('12y12M').class               # => ::Fugit::Duration
Fugit.parse('every day at noon').class    # => ::Fugit::Cron
Fugit.parse('nada')                       # => nil
