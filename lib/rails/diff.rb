# frozen_string_literal: true

require_relative "diff/version"
require "rails"
require "thor"
require "diffy"
require "tmpdir"
require "fileutils"

module Rails
  module Diff
    class Error < StandardError; end

    RAILS_REPO = "https://github.com/rails/rails.git"

    class << self
      def for(*files)
        Dir.mktmpdir do |dir|
          app_name = File.basename(Dir.pwd)
          generate_rails_app(dir, app_name)

          files.map do |file|
            diff = diff_file(dir, app_name, file)
            next diff unless diff.is_a?(String)

            [
              "\n#{file} diff:",
              "=" * (10 + file.length),
              diff
            ].join("\n")
          end.join("\n")
        end
      end

      private

      def diff_file(dir, app_name, file)
        rails_file = File.join(dir, app_name, file)
        repo_file = File.join(Dir.pwd, file)

        return "File #{file} not found in Rails template" unless File.exist?(rails_file)
        return "File #{file} not found in your repository" unless File.exist?(repo_file)

        Diffy::Diff.new(
          File.read(rails_file),
          File.read(repo_file),
          include_diff_info: true,
          context: 2
        ).to_s(:color)
      end

      def generate_rails_app(dir, app_name)
        rails_source_path = File.join(dir, "rails")

        Dir.chdir(dir) do
          puts "Cloning Rails from main branch..."
          system("git clone --depth 1 #{RAILS_REPO} rails >/dev/null 2>&1")

          Dir.chdir("rails/railties") do
            puts "Installing Rails dependencies..."
            system("bundle install >/dev/null 2>&1")
            puts "Generating new Rails application..."
            system("bundle exec rails new ../../#{app_name} --force --no-deps --skip-bundle --skip-test --skip-system-test --quiet")
          end
        end
      end
    end

    class CLI < Thor
      desc "diff FILE [FILE ...]", "Compare one or more files from your repository with Rails' generated version"
      def diff(*files)
        abort "Please provide at least one file to compare" if files.empty?

        puts Rails::Diff.for(*files)
      end

      desc "--version, -v", "Show version"
      def version
        puts Rails::Diff::VERSION
      end
    end
  end
end
