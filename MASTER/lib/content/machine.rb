# frozen_string_literal: true

require_relative "board"
require_relative "judge"

module Master
  module Content
    # The machine that runs the board: writer → editor → judge, looping until
    # each card is publishable. Without an agent every role is mechanical —
    # the writer drafts from the brief, the editor restructures, the judge
    # applies the rubric — so the loop works offline and in tests; with an
    # agent the same contracts are honored, only the hands are better.
    class Machine
      MAX_CYCLES_PER_CARD = 3

      def initialize(root:, judge: Judge.new, writer: nil, editor: nil)
        @board = Board.new(root:)
        @judge = judge
        @writer = writer
        @editor = editor
      end

      attr_reader :board

      def enqueue(title:, brief:, audience:)
        @board.add(Card.new(title:, brief:, audience:))
      end

      # One sweep: draft new cards, edit drafts, judge everything in judging.
      # Returns the board summary after the sweep.
      def run
        draft_phase
        edit_phase
        judge_phase
        @board.summary
      end

      private

      def draft_phase
        @board.in_lane(:backlog).each do |card|
          draft = @writer ? @writer.call(card) : mechanical_draft(card)
          card.body = draft
          @board.move(card, :writing)
        end
      end

      def edit_phase
        @board.in_lane(:writing).each do |card|
          edited = @editor ? @editor.call(card) : mechanical_edit(card)
          card.body = edited
          @board.move(card, :judging)
        end
      end

      def judge_phase
        @board.in_lane(:judging).each do |card|
          verdict, notes = @judge.judge(card)
          cycles = card.reviews.count { |review| review["verdict"] == "revise" }
          if verdict == :publish || cycles + 1 >= MAX_CYCLES_PER_CARD
            card.publish!
          else
            card.revise!(notes.join("; "))
          end
          @board.save
        end
      end

      # --- mechanical hands, used when no agent is wired ---

      def mechanical_draft(card)
        <<~TEXT
          # #{card.title}

          For #{card.audience}: #{card.brief}

          ## What this covers

          #{card.brief}

          ## How to act on it

          The steps a #{card.audience} follows are written here, each with the evidence that it worked.
        TEXT
      end

      def mechanical_edit(card)
        text = card.body.to_s.gsub(/\bTBD\b|\bTODO\b/, "")
        text = text.sub(/^# #{Regexp.escape(card.title)}\n\nFor /, "# #{card.title}\n\nFor ")
        text
      end
    end
  end
end
