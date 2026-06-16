# frozen_string_literal: true

# Multi-tradition scripture data for comparisons & visualizations.
# Idempotent: safe to run in production after migrations.

def seed_book!(abbreviation:, name:, tradition:, order_index:)
  Book.find_or_create_by!(abbreviation: abbreviation) do |book|
    book.name = name
    book.tradition = tradition
    book.order_index = order_index
  end
end

def seed_chapter!(book, number:)
  book.chapters.find_or_create_by!(number: number)
end

def seed_verse!(chapter, number:, content:)
  chapter.verses.find_or_create_by!(number: number) do |verse|
    verse.book = chapter.book
    verse.content = content
  end
end

genesis = seed_book!(abbreviation: "Gen", name: "Genesis", tradition: "bible", order_index: 1)
john    = seed_book!(abbreviation: "Jn", name: "John", tradition: "bible", order_index: 43)

gen_ch1 = seed_chapter!(genesis, number: 1)
seed_verse!(gen_ch1, number: 1, content: "In the beginning God created the heavens and the earth.")
seed_verse!(gen_ch1, number: 3, content: "And God said, Let there be light: and there was light.")
seed_verse!(gen_ch1, number: 27, content: "So God created man in his own image, in the image of God created he him; male and female created he them.")

jn_ch3 = seed_chapter!(john, number: 3)
seed_verse!(jn_ch3, number: 16, content: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.")
seed_verse!(jn_ch3, number: 17, content: "For God sent not his Son into the world to condemn the world; but that the world through him might be saved.")

fatiha = seed_book!(abbreviation: "Fatiha", name: "Al-Fatiha", tradition: "quran", order_index: 100)
baqara = seed_book!(abbreviation: "Baqarah", name: "Al-Baqarah", tradition: "quran", order_index: 101)

fatiha_ch = seed_chapter!(fatiha, number: 1)
seed_verse!(fatiha_ch, number: 1, content: "In the name of Allah, the Most Gracious, the Most Merciful.")
seed_verse!(fatiha_ch, number: 2, content: "All praise is for Allah—Lord of all worlds.")
seed_verse!(fatiha_ch, number: 5, content: "You alone we worship and You alone we ask for help.")

baqara_ch2 = seed_chapter!(baqara, number: 2)
seed_verse!(baqara_ch2, number: 255, content: "Allah! There is no god but He, the Living, the Self-Subsisting, Eternal.")
seed_verse!(baqara_ch2, number: 256, content: "Let there be no compulsion in religion.")

gita = seed_book!(abbreviation: "Gita", name: "Bhagavad Gita", tradition: "gita", order_index: 200)
gita_ch2 = seed_chapter!(gita, number: 2)
seed_verse!(gita_ch2, number: 47, content: "You have a right to perform your prescribed duties, but you are not entitled to the fruits of your actions.")
seed_verse!(gita_ch2, number: 48, content: "Perform your duty equipoised, O Arjuna, abandoning all attachment to success or failure. Such equanimity is called yoga.")

gita_ch18 = seed_chapter!(gita, number: 18)
seed_verse!(gita_ch18, number: 66, content: "Abandon all varieties of dharma and just surrender unto Me. I shall deliver you from all sinful reactions. Do not fear.")

[
  [Verse.find_by(content: /In the beginning God created/), Verse.find_by(content: /In the name of Allah/), "thematic"],
  [Verse.find_by(content: /In the beginning God created/), Verse.find_by(content: /You have a right to perform/), "thematic"],
  [Verse.find_by(content: /For God so loved the world/), Verse.find_by(content: /All praise is for Allah/), "thematic"],
  [Verse.find_by(content: /For God so loved the world/), Verse.find_by(content: /Abandon all varieties of dharma/), "parallel"],
  [Verse.find_by(content: /You have a right to perform/), Verse.find_by(content: /Let there be no compulsion/), "thematic"]
].each do |source, target, kind|
  next unless source && target
  CrossReference.find_or_create_by!(verse: source, target_verse: target, kind: kind)
end

puts "baibl multi-tradition seeds complete: Bible, Quran, Bhagavad Gita + cross-theme links."