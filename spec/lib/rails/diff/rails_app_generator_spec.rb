# frozen_string_literal: true

require "rails/diff/rails_app_generator"

RSpec.describe Rails::Diff::RailsAppGenerator do
  let(:cache_dir) { Dir.mktmpdir }
  let(:work_dir) { Dir.mktmpdir("myapp") }

  around do |example|
    original_home = ENV["HOME"]
    ENV["HOME"] = work_dir
    Dir.chdir(work_dir) { example.run }
  ensure
    ENV["HOME"] = original_home
    FileUtils.rm_rf(cache_dir)
    FileUtils.rm_rf(work_dir)
  end

  def build_generator(ref: "abc1234567890def", logger: spy, rails_repo: spy(latest_commit: ref, up_to_date?: false), **options)
    described_class.new(ref:, logger:, cache_dir:, rails_repo:, **options)
  end

  def stub_command(*args, result: true, **opts)
    allow(Rails::Diff::Shell).to receive(:run!).with(*args, **opts).and_return(result)
  end

  describe "#create_template_app" do
    it "checks out the ref, installs dependencies, and generates a new app" do
      repo = spy(latest_commit: "abc1234567890def", up_to_date?: false)
      generator = build_generator(rails_repo: repo)

      generator.create_template_app

      expect(repo).to have_received(:checkout).with("abc1234567890def")
      expect(repo).to have_received(:install_dependencies)
      expect(repo).to have_received(:new_app).with(generator.template_app_path, [])
    end

    it "passes new_app_options to rails new" do
      repo = spy(latest_commit: "abc1234567890def", up_to_date?: false)
      generator = build_generator(rails_repo: repo, new_app_options: "--api --skip-test")

      generator.create_template_app

      expect(repo).to have_received(:new_app).with(
        generator.template_app_path,
        ["--api", "--skip-test"]
      )
    end

    it "merges options from .railsrc when it exists" do
      File.write(File.join(work_dir, ".railsrc"), "--skip-test\n")
      repo = spy(latest_commit: "abc1234567890def", up_to_date?: false)
      logger = spy
      generator = build_generator(rails_repo: repo, logger:, new_app_options: "--api")

      generator.create_template_app

      expect(repo).to have_received(:new_app).with(
        generator.template_app_path,
        ["--api", "--skip-test\n"]
      )
      expect(logger).to have_received(:info).with(/Using default options from/)
    end

    it "defaults ref to the latest commit from the rails repo" do
      repo = spy(latest_commit: "abc1234567890def", up_to_date?: false)
      generator = described_class.new(logger: spy, cache_dir:, rails_repo: repo)

      generator.create_template_app

      expect(repo).to have_received(:checkout).with("abc1234567890def")
    end

    it "skips creation when the app is cached and up to date" do
      repo = spy(latest_commit: "abc1234567890def", up_to_date?: true)
      generator = build_generator(rails_repo: repo)
      FileUtils.mkdir_p(generator.template_app_path)

      generator.create_template_app

      expect(repo).not_to have_received(:checkout)
      expect(repo).not_to have_received(:new_app)
    end

    it "recreates the app when the repo is outdated" do
      repo = spy(latest_commit: "abc1234567890def", up_to_date?: false)
      generator = build_generator(rails_repo: repo)
      FileUtils.mkdir_p(generator.template_app_path)

      generator.create_template_app

      expect(repo).to have_received(:checkout).with("abc1234567890def")
      expect(repo).to have_received(:new_app)
    end
  end

  describe "#clear_cache" do
    it "removes and recreates the cache directory" do
      generator = build_generator
      marker = File.join(cache_dir, "some_cached_file")
      FileUtils.touch(marker)

      generator.clear_cache

      expect(File.exist?(marker)).to eq(false)
      expect(Dir.exist?(cache_dir)).to eq(true)
    end

    it "is called on initialization when no_cache is true" do
      repo = spy(latest_commit: "abc1234567890def", up_to_date?: false)
      marker = File.join(cache_dir, "some_cached_file")
      FileUtils.touch(marker)

      build_generator(rails_repo: repo, no_cache: true)

      expect(File.exist?(marker)).to eq(false)
      expect(Dir.exist?(cache_dir)).to eq(true)
    end
  end

  describe "#template_app_path" do
    it "includes the ref prefix in the path" do
      generator = build_generator

      expect(generator.template_app_path).to include("rails-abc1234567")
    end

    it "uses the current directory name as the app name" do
      generator = build_generator

      expect(generator.template_app_path).to end_with(File.basename(work_dir))
    end

    it "generates different paths for different options" do
      gen1 = build_generator(new_app_options: "--api")
      gen2 = build_generator(new_app_options: "--skip-test")

      expect(gen1.template_app_path).not_to eq(gen2.template_app_path)
    end
  end

  describe "#install_app_dependencies" do
    it "runs bundle install when bundle check fails" do
      logger = spy
      generator = build_generator(logger:)
      FileUtils.mkdir_p(generator.template_app_path)

      stub_command("bundle check", abort: false, logger:, result: false)
      stub_command("bundle install", logger:)

      generator.install_app_dependencies

      expect(Rails::Diff::Shell).to have_received(:run!).with("bundle install", logger:)
    end

    it "skips bundle install when bundle check passes" do
      logger = spy
      generator = build_generator(logger:)
      FileUtils.mkdir_p(generator.template_app_path)

      stub_command("bundle check", abort: false, logger:, result: true)

      generator.install_app_dependencies

      expect(Rails::Diff::Shell).not_to have_received(:run!).with("bundle install", logger:)
    end
  end

  describe "#run_generator" do
    it "destroys existing files and regenerates them" do
      logger = spy
      generator = build_generator(logger:)
      FileUtils.mkdir_p(generator.template_app_path)

      stub_command("bin/rails", "destroy", "model", "User", logger:)
      stub_command("bin/rails", "generate", "model", "User", logger:)
      allow(Rails::Diff::FileTracker).to receive(:new_files)
        .and_yield
        .and_return(["#{generator.template_app_path}/app/models/user.rb"])

      generator.run_generator("model", "User", [], [])

      expect(Rails::Diff::Shell).to have_received(:run!)
        .with("bin/rails", "destroy", "model", "User", logger:)
      expect(Rails::Diff::Shell).to have_received(:run!)
        .with("bin/rails", "generate", "model", "User", logger:)
    end

    it "returns relative file paths" do
      generator = build_generator
      FileUtils.mkdir_p(generator.template_app_path)

      stub_command("bin/rails", "destroy", "model", "User", logger: anything)
      stub_command("bin/rails", "generate", "model", "User", logger: anything)
      allow(Rails::Diff::FileTracker).to receive(:new_files)
        .and_return([
          "#{generator.template_app_path}/app/models/user.rb",
          "#{generator.template_app_path}/db/migrate/001_create_users.rb"
        ])

      result = generator.run_generator("model", "User", [], [])

      expect(result).to eq(["app/models/user.rb", "db/migrate/001_create_users.rb"])
    end
  end
end
