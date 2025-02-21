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
        generate_template_app(app_name)

        files.map do |file|
          header = "#{file} diff:"
          [
            header,
            "=" * header.size,
            diff_file(app_name, file)
          ].join("\n")
        end.join("\n")
      end

      def generated(generator_name, *args)
        app_name = File.basename(Dir.pwd)
        generate_template_app(app_name)

        template_app_path = File.join(CACHE_DIR, app_name)

        Dir.chdir(template_app_path) do
          system("bin/rails destroy #{generator_name} #{args.join(' ')} --quiet >/dev/null 2>&1")
        end

        files_before = list_files(template_app_path)

        Dir.chdir(template_app_path) do
          puts "Running generator: rails generate #{generator_name} #{args.join(' ')}"
          system("bin/rails generate #{generator_name} #{args.join(' ')} --quiet")
        end

        files_after = list_files(template_app_path)
        new_files = files_after - files_before

        new_files.map do |file|
          relative_path = file.delete_prefix("#{template_app_path}/")
          [
            "#{relative_path} diff:",
            "=" * (10 + relative_path.length),
            diff_file(app_name, relative_path)
          ].join("\n")
        end.join("\n")
      end

      private

      def list_files(dir)
        Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH)
           .reject { |f| File.directory?(f) }
           .reject { |f| f.end_with?(".git") }
           .reject { |f| f.start_with?("#{dir}/tmp") }
      end

      def diff_file(app_name, file)
        rails_file = File.join(CACHE_DIR, app_name, file)
        repo_file = File.join(Dir.pwd, file)

        return "#{file} not found in Rails template" unless File.exist?(rails_file)
        return "#{file} not found in your repository" unless File.exist?(repo_file)

        Diffy::Diff.new(
          File.read(rails_file),
          File.read(repo_file),
          include_diff_info: true,
          context: 2
        ).to_s(:color)
      end

      def generate_template_app(app_name)
        FileUtils.mkdir_p(CACHE_DIR)
        template_app_path = File.join(CACHE_DIR, app_name)
        rails_path = File.join(CACHE_DIR, "rails")

        return if cached_app?(template_app_path, rails_path)

        FileUtils.rm_rf(template_app_path)
        generate_rails_app(template_app_path, rails_path)
      end

      def cached_app?(template_app_path, rails_path)
        File.exist?(template_app_path) && !rails_updated?(rails_path)
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

      def generate_rails_app(template_app_path, rails_path)
        unless File.exist?(rails_path)
          system("git clone --depth 1 #{RAILS_REPO} #{rails_path} >/dev/null 2>&1")
        end

        Dir.chdir(rails_path) do
          commit = `git rev-parse HEAD`.strip
          puts "Using Rails edge (commit #{commit[0..6]})"

          unless system("bundle check >/dev/null 2>&1")
            puts "Installing Rails dependencies..."
            system("bundle install >/dev/null 2>&1")
          end

          Dir.chdir("railties") do
            puts "Generating new Rails application..."
            system("bundle exec rails new #{template_app_path} --main --skip-bundle --force --skip-test --skip-system-test --quiet")
          end
        end

        Dir.chdir(template_app_path) do
          puts "Installing application dependencies..."
          system("bundle install >/dev/null 2>&1")
        end
      end
    end

    class CLI < Thor
      desc "diff FILE [FILE ...]", "Compare one or more files from your repository with Rails' generated version"
      def diff(*files)
        abort "Please provide at least one file to compare" if files.empty?

        puts Rails::Diff.for(*files)
      end

      desc "generated GENERATOR [args]", "Compare files that would be created by a Rails generator"
      def generated(generator_name, *args)
        puts Rails::Diff.generated(generator_name, *args)
      end
    end
  end
end
