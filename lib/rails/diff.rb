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
      def file(*files, no_cache: false)
        clear_cache if no_cache
        ensure_template_app_exists

        files.filter_map { |it| diff_with_header(it) }.join("\n")
      end

      def generated(generator_name, *args, no_cache: false, skip: [])
        clear_cache if no_cache
        ensure_template_app_exists
        install_app_dependencies

        generated_files(generator_name, *args, skip)
          .map { |it| diff_with_header(it) }
          .join("\n\n")
      end

      private

      def app_name
        @app_name ||= File.basename(Dir.pwd)
      end

      def template_app_path
        @template_app_path ||= File.join(CACHE_DIR, app_name)
      end

      def rails_path
        @rails_path ||= File.join(CACHE_DIR, "rails")
      end

      def clear_cache
        puts "Clearing cache..."
        FileUtils.rm_rf(CACHE_DIR)
      end

      def list_files(dir, skip = [])
        Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).reject do |it|
          File.directory?(it) ||
            it.start_with?("#{dir}/.git") ||
            it.start_with?("#{dir}/tmp") ||
            it.start_with?("#{dir}/log") ||
            it.start_with?("#{dir}/test") ||
            skip.any? { |s| it.start_with?("#{dir}/#{s}") }
        end
      end

      def track_new_files(skip)
        files_before = list_files(template_app_path)
        yield
        files_after = list_files(template_app_path, skip)
        files_after - files_before
      end

      def generated_files(generator_name, *args, skip)
        command = "#{generator_name} #{args.join(' ')}"
        Dir.chdir(template_app_path) do
          system("bin/rails destroy #{command} >/dev/null 2>&1")
          puts "Running generator: rails generate #{command}"
          track_new_files(skip) { system("bin/rails generate #{command} > /dev/null 2>&1") }
            .map { |it| it.delete_prefix("#{template_app_path}/") }
        end
      end

      def diff_with_header(file)
        diff = diff_file(file)
        return if diff.empty?

        header = "#{file} diff:"
        [header, "=" * header.size, diff].join("\n")
      end

      def install_app_dependencies
        Dir.chdir(template_app_path) do
          unless system("bundle check >/dev/null 2>&1")
            puts "Installing application dependencies..."
            system("bundle install >/dev/null 2>&1")
          end
        end
      end

      def diff_file(file)
        rails_file = File.join(template_app_path, file)
        repo_file = File.join(Dir.pwd, file)

        return "#{file} not found in the Rails template" unless File.exist?(rails_file)
        return "#{file} not found in your repository" unless File.exist?(repo_file)

        Diffy::Diff.new(
          rails_file,
          repo_file,
          context: 2,
          source: 'files'
        ).to_s(:color).chomp
      end

      def ensure_template_app_exists
        FileUtils.mkdir_p(CACHE_DIR)

        return if cached_app?

        FileUtils.rm_rf(template_app_path)
        create_new_rails_app
      end

      def cached_app?
        File.exist?(template_app_path) && !rails_updated?
      end

      def rails_updated?
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

      def create_new_rails_app
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
      end
    end

    class CLI < Thor
      class_option :no_cache, type: :boolean, desc: "Clear cache before running", aliases: ["--clear-cache"]
      def self.exit_on_failure? = true

      desc "file FILE [FILE ...]", "Compare one or more files from your repository with Rails' generated version"
      def file(*files)
        abort "Please provide at least one file to compare" if files.empty?

        diff = Rails::Diff.file(*files, no_cache: options[:no_cache])
        return if diff.empty?

        puts diff
      end

      desc "generated GENERATOR [args]", "Compare files that would be created by a Rails generator"
      option :skip, type: :array, desc: "Skip specific files or directories", aliases: ["-s"], default: []
      def generated(generator_name, *args)
        diff = Rails::Diff.generated(generator_name, *args, no_cache: options[:no_cache], skip: options[:skip])
        return if diff.empty?

        puts diff
      end
    end
  end
end
