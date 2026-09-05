# frozen_string_literal: true

require 'open3'

readme = File.read("MASTER/README.md")
text = readme.gsub(/#+ /, '').gsub(/\[.*?\]\(.*?\)/, '\1').gsub(/<.*?>/, '').strip
paragraphs = text.split("\n\n")

translations = {
  "MASTER is the first artificial intelligence written in pure Ruby that governs itself by law, not by hope — grown in Norway, to run its own mind on power drawn from inside a fjord mountain." => "MASTER er den første kunstige intelligensen skrevet i ren Ruby som styrer seg selv etter loven, ikke etter håp — vokst i Norge, for å kjøre sitt eget sinn på kraft hentet fra innsiden av et fjordfjell.",
  "This is both the project and its business plan — the case for building it here, with Innovasjon Norge." => "Dette er både prosjektet og forretningsplanen — saken for å bygge det her, sammen med Innovasjon Norge.",
  "Ninety-nine percent of AI is written in Python, chosen for its libraries, not its clarity. MASTER is written in pure Ruby — and that is the whole point." => "Nittini prosent av AI er skrevet i Python, valgt for bibliotekene, ikke for klarheten. MASTER er skrevet i ren Ruby — og det er hele poenget.",
  "It runs offline, deploys to OpenBSD, and needs no cloud to judge a codebase — so it can run on hardware we own." => "Det kjører offline, distribueres til OpenBSD, og trenger ingen sky for å dømme en kodebase — slik at det kan kjøre på maskinvare vi eier.",
  "The world spends more on machine intelligence than on almost anything else, and nearly all of it burns electricity in large buildings." => "Verden bruker mer på maskinintelligens enn på nesten noe annet, og nesten alt av det brenner elektrisitet i store bygninger.",
  "The heart of it sits inside a mountain on a Norwegian fjord — the model Lefdal Mine and Green Mountain already prove." => "Hjertet av det sitter inne i et fjell i en norsk fjord — modellen Lefdal Mine og Green Mountain beviser allerede.",
  "Norway's grid is ~98% renewable hydropower, among the cheapest in Europe, and fjord water near 8 °C cools the hall for free." => "Norges strømnett er ~98% fornybar vannkraft, blant de billigste i Europa, og fjordvann nær 8 °C kjøler hallen gratis.",
  "Roughly six million kroner from Innovasjon Norge — Commercialisation Phase 1 near one million, a path to Phase 2 up to four, the startup loan up to two." => "Omtrent seks millioner kroner fra Innovasjon Norge — kommersialiseringsfase 1 nær én million, en vei til fase 2 opptil fire, oppstartslånet opptil to.",
  "MASTER is built like an embryo — one small core of identity, memory, and safety that takes on whatever body a mission needs." => "MASTER er bygget som et embryo — en liten kjerne av identitet, minne og sikkerhet som tar på seg hvilken kropp som helst oppdraget trenger.",
  "Wake it with one line and it comes up like an old Unix machine, telling you what it is and what it runs on." => "Vekk det med én linje og det starter opp som en gammel Unix-maskin, og forteller deg hva det er og hva det kjører på."
}

intro = "Dette arbeidet er dedikert til Innovasjon Norge."
tts_bin = "MASTER/web/vendor/bundle/ruby/3.4.0/bundler/gems/rb-edge-tts-9d7bbcd16cba/exe/rb-edge-tts"

output_files = []

# Pernille intro
`#{tts_bin} --voice no-NO-CecilieNeural "#{intro}" > intro.wav`
# Wait, rb-edge-tts might not use -o, let's check help or use redirection. 
# The error said "invalid option: -o". Most CLI tools like this output to stdout or have a specific flag.
# I'll try redirection.

# Actually, let's check the help for rb-edge-tts first.
