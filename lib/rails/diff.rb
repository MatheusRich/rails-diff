# frozen_string_literal: true

require_relative "diff/version"
require "rails"
require "thor"
require "diffy"
require "fileutils"

module Rails
  module Diff
    class Error < StandardError; end

    RAILS_REPO = "https://github.com/rails/rails.git"
    CACHE_DIR = File.expand_path("~/.rails-diff/cache")

    class << self
      def for(*files)
        app_name = File.basename(Dir.pwd)
        ensure_rails_app_exists(app_name)

        files.map do |file|
          [
            "#{file} diff:",
            "=" * (10 + file.length),
            diff_file(app_name, file)
          ].join("\n")
        end.join("\n")
      end

      private

      def diff_file(app_name, file)
        rails_file = File.join(CACHE_DIR, app_name, file)
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

      def ensure_rails_app_exists(app_name)
        FileUtils.mkdir_p(CACHE_DIR)
        app_path = File.join(CACHE_DIR, app_name)
        rails_path = File.join(CACHE_DIR, "rails")

        return if cached_app?(app_path, rails_path)

        FileUtils.rm_rf(app_path)
        generate_rails_app(app_path, rails_path)
      end

      def cached_app?(app_path, rails_path)
        File.exist?(app_path) && !rails_updated?(rails_path)
      end

      def rails_updated?(rails_path)
        return true if !File.exist?(rails_path)

        Dir.chdir(rails_path) do
          system("git fetch origin main >/dev/null 2>&1")
          current = `git rev-parse HEAD`.strip
          latest = `git rev-parse origin/main`.strip

          if current != latest
            FileUtils.rm_rf(rails_path)
            return true
          end
        end

        false
      end

      def generate_rails_app(app_path, rails_path)
        unless File.exist?(rails_path)
          system("git clone --depth 1 #{RAILS_REPO} #{rails_path} >/dev/null 2>&1")
        end

        Dir.chdir(rails_path) do
          commit = `git rev-parse HEAD`.strip
          puts "Using Rails #{commit[0..6]}"

          unless system("bundle check >/dev/null 2>&1")
            puts "Installing Rails dependencies..."
            system("bundle install >/dev/null 2>&1")
          end

          Dir.chdir("railties") do
            puts "Generating new Rails application..."
            system("bundle exec rails new #{app_path} --force --no-deps --skip-bundle --skip-test --skip-system-test --quiet")
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

      desc "version", "Show version"
      def version
        puts Rails::Diff::VERSION
      end
    end
  end
end
