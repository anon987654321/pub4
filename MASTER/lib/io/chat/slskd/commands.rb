# frozen_string_literal: true

require_relative "../transport"

module Master
  module Io
    module Chat
      class Slskd < Transport
        # The operator-typed surface: `/slsk <word> ...`. Each method shows
        # dmesg lines and returns them. Nothing here is offered to a model.
        module Commands
          USAGE = "slsk0: usage: status | search <text> | results | browse <user> | rooms | room <name> | " \
                  "pm <user> | join <room> | leave <room> | queue | get <n>"
          MAX_RESULTS = 100
          MAX_USERS = 60
          POLLS = 20

          def command(line)
            word, rest = line.to_s.strip.split(/\s+/, 2)
            lines = dispatch(word.to_s.downcase, rest.to_s.strip)
            lines.each { |l| show(l) }
            lines
          rescue Client::Refused, Quarantine::Refused, Http::Error, ArgumentError => e
            msg = ["slsk0: #{scrub(e)}"]
            msg.each { |l| show(l) }
            msg
          end

          private

          def dispatch(word, rest)
            case word
            when "status", "" then [status]
            when "search" then search(rest)
            when "results" then result_lines
            when "browse" then browse(rest)
            when "rooms" then ["slsk0: rooms #{Array(client.rooms_joined).map { |r| clean(r, 60) }.join(" ")}"]
            when "room" then recent(Array(client.room_messages(rest)), "room:#{clean(rest, 60)}")
            when "pm" then recent(Array(client.conversation_messages(rest)), "pm:#{clean(rest, 40)}")
            when "join" then [join(rest)]
            when "leave" then [part(rest)]
            when "queue" then queue
            when "get" then get(rest)
            else [USAGE]
            end
          end

          def search(text)
            raise ArgumentError, "search needs text" if text.empty?

            id = client.create_search(Policy.sanitize(text, max: 200))
            POLLS.times do
              break if complete?(client.search(id))

              @sleeper.call(1)
            end
            @results = flatten(client.search_responses(id))
            ["slsk0: search #{@results.size} files (showing #{[@results.size, MAX_RESULTS].min})"] + result_lines
          end

          def complete?(search)
            return false unless search.is_a?(Hash)

            flag = field(search, :isComplete)
            flag == true || field(search, :state).to_s.include?("Completed")
          end

          # UNVERIFIED field names: username, uploadSpeed, files[].filename/size/bitRate.
          def flatten(responses)
            rows = []
            Array(responses).first(MAX_USERS).each do |resp|
              Array(field(resp, :files)).each do |file|
                rows << { user: field(resp, :username).to_s, speed: field(resp, :uploadSpeed).to_i,
                          filename: field(file, :filename).to_s, size: field(file, :size).to_i,
                          bitrate: field(file, :bitRate) }
                return rows if rows.size >= MAX_RESULTS
              end
            end
            rows
          end

          def result_lines
            return ["slsk0: no results; /slsk search <text>"] if @results.empty?

            @results.each_with_index.map do |r, i|
              rate = r[:bitrate] ? "#{r[:bitrate]}k" : "-"
              "slsk0: [#{i + 1}] #{mb(r[:size])}MB #{rate} #{clean(r[:user], 40)} #{mb(r[:speed])}MB/s " \
                "#{clean(File.basename(r[:filename].tr("\\", "/")), 90)}"
            end
          end

          # Metadata only: directory names and counts, never file contents.
          def browse(user)
            raise ArgumentError, "browse needs a username" if user.empty?

            dirs = Array(client.browse(user))
            ["slsk0: browse #{clean(user, 40)} #{dirs.size} directories"] +
              dirs.first(40).map do |d|
                "slsk0:   #{clean(field(d, :name) || field(d, :directory), 100)} (#{Array(field(d, :files)).size} files)"
              end
          end

          def recent(messages, room)
            messages.last(15).map do |m|
              "slsk0: #{room} <#{clean(field(m, :username), 40)}> #{Policy.sanitize(field(m, :message))}"
            end.then { |l| l.empty? ? ["slsk0: #{room} no messages"] : l }
          end

          def queue
            rows = []
            Array(client.downloads).each do |group|
              Array(field(group, :directories)).each do |dir|
                Array(field(dir, :files)).each do |f|
                  rows << "slsk0: #{clean(field(group, :username), 40)} #{clean(File.basename(field(f, :filename).to_s.tr("\\", "/")), 80)} " \
                          "#{clean(field(f, :state), 40)} #{field(f, :percentComplete).to_f.round}%"
                end
              end
            end
            rows.empty? ? ["slsk0: no downloads queued"] : rows.first(50)
          end

          # One numbered result, nothing else: no ranges, lists or wildcards.
          def get(arg)
            raise ArgumentError, "get takes one result number" unless arg.match?(/\A\d{1,4}\z/)

            row = (arg.to_i.positive? && @results[arg.to_i - 1]) or raise ArgumentError, "no result #{arg}; run /slsk search first"
            base = quarantine.vet!(row[:filename], row[:size])
            quarantine.prepare!
            lines = quarantine.first_notice? ? [Quarantine::NOTICE] : []
            client.enqueue(row[:user], row[:filename], row[:size])
            lines + ["slsk0: queued #{clean(base, 90)} #{mb(row[:size])}MB from #{clean(row[:user], 40)} " \
                     "-> slskd downloads (quarantine #{quarantine.dir}); not opened"]
          end

          def clean(text, max) = Policy.sanitize(text, max:)
          def mb(bytes) = (bytes.to_i / 1024.0 / 1024).round(1)
        end
      end
    end
  end
end
