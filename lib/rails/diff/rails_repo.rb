module Rails
  module Diff
    class RailsRepo
      RAILS_REPO = "https://github.com/rails/rails.git"

      def initialize(logger:, cache_dir: Rails::Diff::CACHE_DIR, rails_repo: RAILS_REPO)
        @logger = logger
        @cache_dir = cache_dir
        @rails_repo = rails_repo
      end

      def checkout(commit)
        on_rails_dir do
          logger.info "Checking out Rails (at commit #{commit[0..6]})"
          Rails::Diff.system!("git", "checkout", commit, logger: logger)
        end
      end

      def latest_commit
        @latest_commit ||= on_rails_dir do
          Rails::Diff.system!("git fetch origin main", logger: logger)
          `git rev-parse origin/main`.strip
        end
      end

      def up_to_date?
        File.exist?(rails_path) && on_latest_commit?
      end

      def install_dependencies
        within "railties" do
          unless Rails::Diff.system!("bundle check", abort: false, logger: logger)
            logger.info "Installing Rails dependencies"
            Rails::Diff.system!("bundle install", logger: logger)
          end
        end
      end

      def new_app(name, options)
        within "railties" do
          command = rails_new_command(name, options)
          logger.info "Generating new Rails application\n\t  > #{command.join(" ")}"
          Rails::Diff.system!(*command, logger: logger)
        end
      end

      def within(dir, &block) = on_rails_dir { Dir.chdir(dir, &block) }

      private

      attr_reader :logger, :cache_dir, :rails_repo

      def rails_path
        File.join(cache_dir, "rails")
      end

      def on_latest_commit?
        if current_commit == latest_commit
          true
        else
          remove_repo
          false
        end
      end

      def on_rails_dir(&block)
        clone_repo unless File.exist?(rails_path)
        Dir.chdir(rails_path, &block)
      end

      def current_commit = on_rails_dir { `git rev-parse HEAD`.strip }

      def remove_repo = FileUtils.rm_rf(rails_path, secure: true)

      def clone_repo
        logger.info "Cloning Rails repository"
        Rails::Diff.system!("git", "clone", "--depth", "1", rails_repo, rails_path, logger: logger)
      end

      def rails_new_command(name, options)
        [
          "bundle", "exec", "rails", "new", name,
          "--main", "--skip-bundle", "--force", "--quiet", *options
        ]
      end
    end
  end
end
