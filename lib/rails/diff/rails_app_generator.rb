require "digest"

module Rails
  module Diff
    class RailsAppGenerator
      RAILSRC_PATH = "#{ENV["HOME"]}/.railsrc"

      def initialize(commit: nil, new_app_options: nil, no_cache: false, logger: Logger, cache_dir: Rails::Diff::CACHE_DIR)
        @new_app_options = new_app_options.to_s.split
        @rails_repo = RailsRepo.new(logger:, cache_dir:)
        @commit = commit
        @logger = logger
        @cache_dir = cache_dir
        clear_cache if no_cache
      end

      def clear_cache
        logger.info "Clearing cache"
        FileUtils.rm_rf(cache_dir, secure: true)
        FileUtils.mkdir_p(cache_dir)
      end

      def create_template_app
        return if cached_app?

        create_new_rails_app
      end

      def template_app_path
        @template_app_path ||= File.join(cache_dir, rails_cache_dir_key, rails_new_options_hash, app_name)
      end

      def install_app_dependencies
        Dir.chdir(template_app_path) do
          unless Shell.run!("bundle check", abort: false, logger:)
            logger.info "Installing application dependencies"
            Shell.run!("bundle install", logger:)
          end
        end
      end

      def run_generator(generator_name, *args, skip, only)
        Dir.chdir(template_app_path) do
          Shell.run!("bin/rails", "destroy", generator_name, *args, logger:)
          logger.info "Running generator: rails generate #{generator_name} #{args.join(" ")}"

          FileTracker
            .new_files(template_app_path, skip:, only:) { Shell.run!("bin/rails", "generate", generator_name, *args, logger:) }
            .map { |it| it.delete_prefix("#{template_app_path}/") }
        end
      end

      private

      attr_reader :new_app_options, :rails_repo, :logger, :cache_dir

      def commit = @commit ||= rails_repo.latest_commit

      def rails_cache_dir_key = "rails-#{commit.first(10)}"

      def railsrc_options
        @railsrc_options ||= File.exist?(RAILSRC_PATH) ? File.readlines(RAILSRC_PATH) : []
      end

      def app_name = @app_name ||= File.basename(Dir.pwd)

      def cached_app?
        File.exist?(template_app_path) && rails_repo.up_to_date?
      end

      def create_new_rails_app
        checkout_rails_commit
        generate_app
      end

      def generate_app
        rails_repo.install_dependencies
        if railsrc_options.any?
          logger.info "Using default options from #{RAILSRC_PATH}:\n\t  > #{railsrc_options.join(" ")}"
        end
        rails_repo.new_app(template_app_path, rails_new_options)
      end

      def checkout_rails_commit = rails_repo.checkout(commit)

      def rails_new_options
        @rails_new_options ||= (new_app_options + railsrc_options).compact
      end

      def rails_new_options_hash
        Digest::MD5.hexdigest(rails_new_options.join(" "))
      end
    end
  end
end
