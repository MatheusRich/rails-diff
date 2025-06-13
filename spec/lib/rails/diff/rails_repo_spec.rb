# Helper indices for commits:
#   git_repo.commits[0] => 'add railties dir' (initial commit)
#   git_repo.commits[1] => 'commit1'
#   git_repo.commits.last => 'commit2'

require "rails/diff/rails_repo"
require "fileutils"
require "tmpdir"

RSpec.describe Rails::Diff::RailsRepo do
  let(:logger) { spy }
  let(:cache_dir) { Dir.mktmpdir }
  let(:rails_path) { File.join(cache_dir, "rails") }
  let(:git_repo) do
    GitRepo.new.tap do |repo|
      repo.add_commit("commit1")
      repo.add_commit("commit2")
    end
  end

  after do
    FileUtils.rm_rf(cache_dir)
    git_repo.cleanup
  end

  describe "#up_to_date?" do
    it "returns false when repo is not cloned yet" do
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      result = repo.up_to_date?

      expect(result).to eq false
    end

    it "returns true when repo is on the latest commit" do
      git_repo.clone_at_commit(git_repo.commits.last, rails_path)
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      result = repo.up_to_date?

      expect(result).to eq true
    end

    it "returns false and removes the repo when repo is on an old commit" do
      git_repo.clone_at_commit(git_repo.commits.first, rails_path)
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      result = repo.up_to_date?

      expect(result).to eq false
      expect(File.exist?(rails_path)).to eq false
    end
  end

  describe "#latest_commit" do
    it "returns the latest commit SHA from the remote repo" do
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      latest = repo.latest_commit

      expect(latest).to eq git_repo.commits.last
    end

    it "returns the new latest commit after a new commit is pushed" do
      new_commit = git_repo.add_commit("commit3")
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      latest = repo.latest_commit

      expect(latest).to eq new_commit
    end
  end

  describe "#checkout" do
    it "checks out the given commit in the repo" do
      git_repo.clone_at_commit(git_repo.commits.last, rails_path)
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      # Checkout the first file commit (not the initial railties commit)
      repo.checkout(git_repo.commits[1])

      # Verify HEAD is now at the first file commit
      current = Dir.chdir(rails_path) { `git rev-parse HEAD`.strip }
      expect(current).to eq git_repo.commits[1]
    end

    it "logs the checkout info message" do
      git_repo.clone_at_commit(git_repo.commits.last, rails_path)
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      repo.checkout(git_repo.commits[1])

      expect(logger).to have_received(:info)
        .with(/Checking out Rails \(at commit #{git_repo.commits[1][0..6]}\)/)
    end
  end

  describe "#install_dependencies" do
    it "runs bundle check and bundle install if needed, and logs appropriately" do
      git_repo.clone_at_commit(git_repo.commits[0], rails_path)
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      # Simulate bundle check failing, so bundle install is needed
      allow(Rails::Diff).to receive(:system!).with("bundle check", abort: false, logger: logger).and_return(false)
      allow(Rails::Diff).to receive(:system!).with("bundle install", logger: logger).and_return(true)

      repo.install_dependencies

      expect(logger).to have_received(:info).with("Installing Rails dependencies")
      expect(Rails::Diff).to have_received(:system!).with("bundle install", logger: logger)
    end

    it "does not run bundle install if bundle check passes" do
      git_repo.clone_at_commit(git_repo.commits[0], rails_path)
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      # Simulate bundle check passing
      allow(Rails::Diff).to receive(:system!).with("bundle check", abort: false, logger: logger).and_return(true)

      repo.install_dependencies

      expect(logger).not_to have_received(:info).with("Installing Rails dependencies")
    end
  end

  describe "#new_app" do
    it "runs the rails new command with the correct arguments and logs the command" do
      git_repo.clone_at_commit(git_repo.commits.last, rails_path)
      repo = described_class.new(logger:, cache_dir:, rails_repo: git_repo.remote_repo)

      allow(Rails::Diff).to receive(:system!).and_return(true)
      app_name = "myapp"
      options = ["--skip-test"]

      repo.new_app(app_name, options)

      expected_command = [
        "bundle", "exec", "rails", "new", app_name,
        "--main", "--skip-bundle", "--force", "--quiet", *options
      ]
      expect(Rails::Diff).to have_received(:system!).with(*expected_command, logger: logger)
      expect(logger).to have_received(:info).with(/Generating new Rails application/)
    end
  end
end
