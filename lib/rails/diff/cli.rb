require "thor"

module Rails
  module Diff
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

        diff = Rails::Diff.file(
          *files,
          no_cache: options[:no_cache],
          commit: options[:commit],
          new_app_options: options[:new_app_options]
        )
        return if diff.empty?

        options[:fail_on_diff] ? abort(diff) : puts(diff)
      end
      end

      desc "generated GENERATOR [args]", "Compare files that would be created by a Rails generator"
      option :skip, type: :array, desc: "Skip specific files or directories", aliases: ["-s"], default: []
      option :only, type: :array, desc: "Only include specific files or directories", aliases: ["-o"], default: []
      def generated(generator_name, *args)
        ENV["DEBUG"] = "true" if options[:debug]
        diff = Rails::Diff.generated(
          generator_name,
          *args,
          no_cache: options[:no_cache],
          skip: options[:skip],
          only: options[:only],
          commit: options[:commit],
          new_app_options: options[:new_app_options]
        )
        return if diff.empty?

        options[:fail_on_diff] ? abort(diff) : puts(diff)
      end

      map %w[--version -v] => :__version
      desc "--version, -v", "print the version"
      def __version
        puts VERSION
      end
    end
  end
end
