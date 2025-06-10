# frozen_string_literal: true

require_relative "diff/version"
require_relative "diff/file_tracker"
require "rails"
require "thor"
require "diffy"
require "fileutils"
require "open3"

module Rails
  module Diff
    class Error < StandardError; end

    RAILS_REPO = "https://github.com/rails/rails.git"
    CACHE_DIR = File.expand_path("#{ENV["HOME"]}/.rails-diff/cache")
    RAILSRC_PATH = "#{ENV["HOME"]}/.railsrc"

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

      def system!(*cmd, abort: true)
        _, stderr, status = Open3.capture3(*cmd)

        debug cmd.join(" ")

        if status.success?
          true
        elsif abort
          $stderr.puts "\e[1;31mCommand failed:\e[0m #{cmd.join(' ')}"
          abort stderr
        else
          false
        end
      end

      def info(message)
        puts "\e[1;34minfo:\e[0m\t#{message}"
      end

      def debug(message)
        return unless ENV["DEBUG"]

        puts "\e[1;33mdebug:\e[0m\t#{message}"
      end

      def clear_cache
        info "Clearing cache"
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
        @template_app_path ||= File.join(CACHE_DIR, "rails-#{commit.first(10)}", rails_new_options_hash, app_name)
      end

      def rails_path
        @rails_path ||= begin
          File.join(CACHE_DIR, "rails").tap do |path|
            unless File.exist?(path)
              info "Cloning Rails repository"
              system!("git", "clone", "--depth", "1", RAILS_REPO, path)
            end
          end
        end
      end

      def railsrc_options
        return @railsrc_options if defined?(@railsrc_options)

        @railsrc_options = File.read(RAILSRC_PATH).lines if File.exist?(RAILSRC_PATH)
      end

      def app_name = @app_name ||= File.basename(Dir.pwd)

      def generated_files(generator_name, *args, skip)
        Dir.chdir(template_app_path) do
          system!("bin/rails", "destroy", generator_name, *args)
          info "Running generator: rails generate #{generator_name} #{args.join(' ')}"
          FileTracker.new.track_new_files(template_app_path, skip) { system!("bin/rails", "generate", generator_name, *args) }
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
          unless system!("bundle check", abort: false)
            info "Installing application dependencies"
            system!("bundle install")
          end
        end
      end

      def diff_file(file)
        rails_file = File.join(template_app_path, file)
        repo_file = File.join(Dir.pwd, file)

        return "File not found in the Rails template" unless File.exist?(rails_file)
        return "File not found in your repository" unless File.exist?(repo_file)

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
          system!("git fetch origin main")
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
        Dir.chdir("railties") do
          unless system!("bundle check", abort: false)
            info "Installing Rails dependencies"
            system!("bundle install")
          end

          if railsrc_options
            info "Using default options from #{RAILSRC_PATH}:\n\t  > #{railsrc_options.join(' ')}"
          end

          info "Generating new Rails application\n\t  > #{rails_new_command.join(' ')}"
          system!(*rails_new_command)
        end
      end

      def checkout_rails
        info "Checking out Rails (at commit #{commit[0..6]})"
        system!("git", "checkout", commit)
      end

      def commit = @commit

      def new_app_options = @new_app_options

      def latest_commit
        Dir.chdir(rails_path) do
          `git rev-parse origin/main`.strip
        end
      end

      def rails_new_command = @rails_new_command ||= [
          "bundle",
          "exec",
          "rails",
          "new",
          template_app_path,
          "--main",
          "--skip-bundle",
          "--force",
          "--quiet",
          *rails_new_options
        ]

      def rails_new_options = @rails_new_options ||= [*new_app_options, *railsrc_options].compact

      def rails_new_options_hash = Digest::MD5.hexdigest(rails_new_options.join(" "))
    end

    class CLI < Thor
      class_option :no_cache, type: :boolean, desc: "Clear cache before running", aliases: ["--clear-cache"]
      class_option :fail_on_diff, type: :boolean, desc: "Fail if there are differences"
      class_option :commit, type: :string, desc: "Compare against a specific commit"
      class_option :new_app_options, type: :string, desc: "Options to pass to the rails new command"
      class_option :debug, type: :boolean, desc: "Print debug information", aliases: ["-d"]

      def self.exit_on_failure? = true

      desc "file FILE [FILE ...]", "Compare one or more files from your repository with Rails' generated version"
      def file(*files)
        abort "Please provide at least one file to compare" if files.empty?
        ENV["DEBUG"] = "true" if options[:debug]

        diff = Rails::Diff.file(*files, no_cache: options[:no_cache], commit: options[:commit], new_app_options: options[:new_app_options])
        return if diff.empty?

        options[:fail] ? abort(diff) : puts(diff)
      end

      desc "generated GENERATOR [args]", "Compare files that would be created by a Rails generator"
      option :skip, type: :array, desc: "Skip specific files or directories", aliases: ["-s"], default: []
      def generated(generator_name, *args)
        ENV["DEBUG"] = "true" if options[:debug]
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
