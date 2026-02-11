module MASTER
  module CLI
    module Suggestions
      # Calculate Levenshtein distance between two strings
      def self.levenshtein_distance(s1, s2)
        return s2.length if s1.empty?
        return s1.length if s2.empty?

        matrix = Array.new(s1.length + 1) { Array.new(s2.length + 1) }

        (0..s1.length).each { |i| matrix[i][0] = i }
        (0..s2.length).each { |j| matrix[0][j] = j }

        (1..s1.length).each do |i|
          (1..s2.length).each do |j|
            cost = s1[i - 1] == s2[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,      # deletion
              matrix[i][j - 1] + 1,      # insertion
              matrix[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        matrix[s1.length][s2.length]
      end

      # Find the closest match from a list of options
      def self.closest_match(input, options, threshold = 3)
        return nil if options.empty?

        distances = options.map { |opt| [opt, levenshtein_distance(input.downcase, opt.downcase)] }
        closest = distances.min_by { |_, dist| dist }
        
        closest[1] <= threshold ? closest[0] : nil
      end

      # Find similar files in directory
      def self.similar_files(target, directory = ".", threshold = 3)
        return [] unless File.directory?(directory)

        files = Dir.glob("#{directory}/**/*").select { |f| File.file?(f) }
        target_basename = File.basename(target)

        similarities = files.map do |file|
          file_basename = File.basename(file)
          [file, levenshtein_distance(target_basename, file_basename)]
        end

        similarities
          .select { |_, dist| dist <= threshold }
          .sort_by { |_, dist| dist }
          .take(5)
          .map { |file, _| file }
      end
    end
  end
end
