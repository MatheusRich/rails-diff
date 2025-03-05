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
      def file(*files, no_cache: false, commit: nil, new_app_options: nil)
        clear_cache if no_cache
        ensure_template_app_exists(commit, new_app_options)

        files.filter_map { |it| diff_with_header(it) }.join("\n")
      end

      def generated(generator_name, *args, no_cache: false, skip: [], commit: nil, new_app_options: nil)
        clear_cache if no_cache
        ensure_template_app_exists(commit, new_app_options)
        install_app_dependencies

        generated_files(generator_name, *args, skip)
          .map { |it| diff_with_header(it) }
          .join("\n\n")
      end

      private

      def clear_cache
        puts "Clearing cache"
        FileUtils.rm_rf(CACHE_DIR)
      end

      def ensure_template_app_exists(commit, new_app_options)
        FileUtils.mkdir_p(CACHE_DIR)
        @new_app_options = new_app_options
        @commit = commit || latest_commit
        return if cached_app?

        create_new_rails_app
      end

      def template_app_path
        @template_app_path ||= File.join(CACHE_DIR, commit, new_app_options_hash, app_name)
      end

      def rails_path
        @rails_path ||= begin
          File.join(CACHE_DIR, "rails").tap do |path|
            unless File.exist?(path)
              system("git clone --depth 1 #{RAILS_REPO} #{path} >/dev/null 2>&1")
            end
          end
        end
      end

      def railsrc_path
        "#{ENV["HOME"]}/.railsrc"
      end

      def railsrc_options
        return @railsrc_options if defined?(@railsrc_options)

        @railsrc_options = File.read(railsrc_path).tr("\n", " ") if File.exist?(railsrc_path)
      end

      def app_name = @app_name ||= File.basename(Dir.pwd)

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
            puts "Installing application dependencies"
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

      def cached_app?
        File.exist?(template_app_path) && !out_of_date_rails?
      end

      def out_of_date_rails?
        return true unless File.exist?(rails_path)

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
        Dir.chdir(rails_path) do
          checkout_rails
          generate_app
        end
      end

      def generate_app
        FileUtils.rm_rf(template_app_path)
        Dir.chdir("railties") do
          unless system("bundle check >/dev/null 2>&1")
            puts "Installing Rails dependencies"
            system("bundle install >/dev/null 2>&1")
          end

          rails_new_command = "bundle exec rails new #{template_app_path} --main --skip-bundle --force --skip-test --skip-system-test --quiet #{new_app_options}"

          if railsrc_options
            rails_new_command = "#{rails_new_command} #{railsrc_options}"

            puts "Using default options from #{railsrc_path}:"
            puts "  > #{railsrc_options}\n\n"
          end

          puts "Generating new Rails application"
          puts "  > #{rails_new_command}\n\n"

          system(rails_new_command)
        end
      end

      def checkout_rails
        puts "Checking out Rails (at commit #{commit[0..6]})"
        system("git checkout #{commit} >/dev/null 2>&1")
      end

      def commit = @commit

      def new_app_options = @new_app_options

      def latest_commit
        Dir.chdir(rails_path) do
          `git rev-parse origin/main`.strip
        end
      end

      def new_app_options_hash
        Digest::SHA256.hexdigest(new_app_options.to_s)
      end
    end

    class CLI < Thor
      class_option :no_cache, type: :boolean, desc: "Clear cache before running", aliases: ["--clear-cache"]
      class_option :fail_on_diff, type: :boolean, desc: "Fail if there are differences"
      class_option :commit, type: :string, desc: "Compare against a specific commit"
      class_option :new_app_options, type: :string, desc: "Options to pass to the rails new command"

      def self.exit_on_failure? = true

      desc "file FILE [FILE ...]", "Compare one or more files from your repository with Rails' generated version"
      def file(*files)
        abort "Please provide at least one file to compare" if files.empty?

        diff = Rails::Diff.file(*files, no_cache: options[:no_cache], commit: options[:commit], new_app_options: options[:new_app_options])
        return if diff.empty?

        options[:fail] ? abort(diff) : puts(diff)
      end

      desc "generated GENERATOR [args]", "Compare files that would be created by a Rails generator"
      option :skip, type: :array, desc: "Skip specific files or directories", aliases: ["-s"], default: []
      def generated(generator_name, *args)
        diff = Rails::Diff.generated(generator_name, *args, no_cache: options[:no_cache], skip: options[:skip], commit: options[:commit], new_app_options: options[:new_app_options])
        return if diff.empty?

        options[:fail] ? abort(diff) : puts(diff)
      end

      map %w[--version -v] => :__version
      desc "--version, -v", "print the version"
      def __version
        puts VERSION
      end
    end
  end
end
