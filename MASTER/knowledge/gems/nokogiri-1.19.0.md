require 'nokogiri'
require 'open-uri'

doc = Nokogiri::HTML(URI.open('https://nokogiri.org/tutorials/installing_nokogiri.html'))
doc.css('nav ul.menu li a', 'article h2').each { |link| puts link.content }
doc.xpath('//nav//ul//li/a', '//article//h2').each { |link| puts link.content }
doc.search('nav ul.menu li a', '//article//h2').each { |link| puts link.content }
