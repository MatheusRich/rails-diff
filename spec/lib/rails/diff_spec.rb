# frozen_string_literal: true

RSpec.describe Rails::Diff do
  let(:template_dir) { Dir.mktmpdir }
  let(:repo_dir) { Dir.mktmpdir("repo") }

  around do |example|
    Dir.chdir(repo_dir) { example.run }
  ensure
    FileUtils.rm_rf(template_dir)
    FileUtils.rm_rf(repo_dir)
  end

  def mock_generator(template_path: template_dir)
    spy(template_app_path: template_path)
  end

  def fake_differ_class(output: "some diff output")
    Class.new do
      define_method(:initialize) { |**| }
      define_method(:diff_files) { |*, **| "#{output}\n" }
    end
  end

  def write_file(dir, path, content)
    full_path = File.join(dir, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  describe ".file" do
    it "returns diff output when files differ" do
      write_file(template_dir, "Gemfile", "gem 'rails'\n")
      write_file(repo_dir, "Gemfile", "gem 'rails'\ngem 'sidekiq'\n")

      result = described_class.file("Gemfile", app_generator: mock_generator, differ_class: fake_differ_class(output: "line changed"))

      expect(result).to include("Gemfile diff:")
      expect(result).to include("line changed")
    end

    it "reports when file is missing from the Rails template" do
      write_file(repo_dir, "custom.rb", "# custom file\n")

      result = described_class.file("custom.rb", app_generator: mock_generator, differ_class: fake_differ_class)

      expect(result).to include("File not found in the Rails template")
    end

    it "reports when file is missing from the repository" do
      write_file(template_dir, "Gemfile", "gem 'rails'\n")

      result = described_class.file("Gemfile", app_generator: mock_generator, differ_class: fake_differ_class)

      expect(result).to include("File not found in your repository")
    end

    it "returns empty string when files are identical" do
      write_file(template_dir, "Gemfile", "gem 'rails'\n")
      write_file(repo_dir, "Gemfile", "gem 'rails'\n")

      result = described_class.file("Gemfile", app_generator: mock_generator, differ_class: fake_differ_class(output: ""))

      expect(result).to eq("")
    end

    it "calls create_template_app on the generator" do
      generator = mock_generator
      write_file(template_dir, "Gemfile", "gem 'rails'\n")
      write_file(repo_dir, "Gemfile", "gem 'rails'\n")

      described_class.file("Gemfile", app_generator: generator, differ_class: fake_differ_class(output: ""))

      expect(generator).to have_received(:create_template_app)
    end
  end

  describe ".infra" do
    it "skips app/ and lib/ directories by default" do
      write_file(template_dir, "app/models/user.rb", "class User; end\n")
      write_file(template_dir, "lib/tasks.rb", "# tasks\n")
      write_file(template_dir, "config/routes.rb", "# routes\n")
      write_file(repo_dir, "config/routes.rb", "# different routes\n")

      result = described_class.infra(app_generator: mock_generator, differ_class: fake_differ_class(output: "routes changed"))

      expect(result).to include("config/routes.rb diff:")
      expect(result).not_to include("app/models")
      expect(result).not_to include("lib/tasks")
    end

    it "merges user skip options with defaults" do
      write_file(template_dir, "config/routes.rb", "# routes\n")
      write_file(template_dir, "bin/rails", "#!/usr/bin/env ruby\n")
      write_file(repo_dir, "config/routes.rb", "# different\n")
      write_file(repo_dir, "bin/rails", "# different\n")

      result = described_class.infra(skip: ["config"], app_generator: mock_generator, differ_class: fake_differ_class(output: "bin changed"))

      expect(result).not_to include("config/routes.rb")
      expect(result).to include("bin/rails diff:")
    end
  end

  describe ".generated" do
    it "installs dependencies and runs the generator" do
      generator = mock_generator
      allow(generator).to receive(:run_generator).and_return([])

      described_class.generated("model", "User", app_generator: generator, differ_class: fake_differ_class)

      expect(generator).to have_received(:create_template_app)
      expect(generator).to have_received(:install_app_dependencies)
      expect(generator).to have_received(:run_generator).with("model", "User", [], [])
    end

    it "diffs generated files" do
      generator = mock_generator
      write_file(template_dir, "app/models/user.rb", "class User; end\n")
      write_file(repo_dir, "app/models/user.rb", "class User < ApplicationRecord; end\n")
      allow(generator).to receive(:run_generator).and_return(["app/models/user.rb"])

      result = described_class.generated("model", "User", app_generator: generator, differ_class: fake_differ_class(output: "model changed"))

      expect(result).to include("app/models/user.rb diff:")
    end
  end
end
