# frozen_string_literal: true

RSpec.describe Rails::Diff, ".cache_dir" do
  around do |example|
    original = ENV["XDG_CACHE_HOME"]
    example.run
  ensure
    ENV["XDG_CACHE_HOME"] = original
  end

  it "uses $XDG_CACHE_HOME/rails-diff when set to an absolute path" do
    ENV["XDG_CACHE_HOME"] = "/tmp/xdg-cache"

    expect(described_class.cache_dir).to eq("/tmp/xdg-cache/rails-diff")
  end

  it "falls back to ~/.cache/rails-diff when unset" do
    ENV.delete("XDG_CACHE_HOME")

    expect(described_class.cache_dir).to eq(File.join(Dir.home, ".cache", "rails-diff"))
  end

  it "ignores an empty $XDG_CACHE_HOME" do
    ENV["XDG_CACHE_HOME"] = ""

    expect(described_class.cache_dir).to eq(File.join(Dir.home, ".cache", "rails-diff"))
  end

  it "ignores a relative $XDG_CACHE_HOME" do
    ENV["XDG_CACHE_HOME"] = "relative/path"

    expect(described_class.cache_dir).to eq(File.join(Dir.home, ".cache", "rails-diff"))
  end
end
