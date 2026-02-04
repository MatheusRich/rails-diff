# frozen_string_literal: true

module Rails
  module Diff
    module FileTracker
      DEFAULT_EXCLUSIONS = %w[.git tmp log test].freeze

      def self.new_files(base_dir, only:, skip: [])
        files_before = list_files(base_dir)
        yield
        files_after = list_files(base_dir, skip:, only:)
        files_after - files_before
      end

      def self.list_files(dir, skip: [], only: [], exclusions: DEFAULT_EXCLUSIONS)
        files = Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).reject do |it|
          File.directory?(it) ||
            exclusions.any? { |e| it.start_with?("#{dir}/#{e}") } ||
            skip.any? { |s| it.start_with?("#{dir}/#{s}") }
        end

        if only.any?
          files.select { |it| only.any? { |o| it.start_with?("#{dir}/#{o}") } }
        else
          files
        end
      end
    end
  end
end
