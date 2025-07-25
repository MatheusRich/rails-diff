# frozen_string_literal: true

module Rails
  module Diff
    class FileTracker
      def initialize(base_dir, skip = [], only = [])
        @base_dir = base_dir
        @skip = skip
        @only = only
      end

      def new_files
        files_before = list_files(@base_dir)
        yield
        files_after = list_files(@base_dir, @skip, @only)
        files_after - files_before
      end

      private

      def list_files(dir, skip = [], only = [])
        files = Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).reject do |it|
          File.directory?(it) ||
            it.start_with?("#{dir}/.git") ||
            it.start_with?("#{dir}/tmp") ||
            it.start_with?("#{dir}/log") ||
            it.start_with?("#{dir}/test") ||
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
