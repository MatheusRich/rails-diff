# frozen_string_literal: true

require "rails"
require "difftastic"
require "fileutils"
require_relative "diff/cli"
require_relative "diff/file_tracker"
require_relative "diff/logger"
require_relative "diff/shell"
require_relative "diff/rails_app_generator"
require_relative "diff/rails_repo"
require_relative "diff/version"

module Rails
  module Diff
    CACHE_DIR = File.expand_path("#{ENV["HOME"]}/.rails-diff/cache")

    class << self
      def file(*files, no_cache: false, commit: nil, new_app_options: nil)
        app_generator = RailsAppGenerator.new(commit:, new_app_options:, no_cache:)
        app_generator.create_template_app

        files
          .filter_map { |it| diff_with_header(it, app_generator.template_app_path) }
          .join("\n")
      end

      def generated(generator_name, *args, no_cache: false, skip: [], only: [], commit: nil, new_app_options: nil)
        app_generator = RailsAppGenerator.new(commit:, new_app_options:, no_cache:)
        app_generator.create_template_app
        app_generator.install_app_dependencies

        app_generator.run_generator(generator_name, *args, skip, only)
          .map { |it| diff_with_header(it, app_generator.template_app_path) }
          .join("\n\n")
      end

      private

      def diff_with_header(file, template_app_path)
        diff = diff_file(file, template_app_path)
        return if diff.empty?

        header = "#{file} diff:"
        [header, "=" * header.size, diff].join("\n")
      end

      def diff_file(file, template_app_path)
        rails_file = File.join(template_app_path, file)
        repo_file = File.join(Dir.pwd, file)

        return "File not found in the Rails template" unless File.exist?(rails_file)
        return "File not found in your repository" unless File.exist?(repo_file)

        differ = Difftastic::Differ.new(
          color: :always,
          left_label: "Rails File (#{file})",
          right_label: "Repo File (#{file})"
        )

        differ.diff_files(rails_file, repo_file).chomp
      end
    end
  end
end
