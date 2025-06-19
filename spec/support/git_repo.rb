require "fileutils"
require "tmpdir"

class GitRepo
  attr_reader :remote_repo, :commits

  # Executes a shell command, suppressing output if successful, but capturing errors if it fails
  def run_command(command)
    result = `#{command} 2>&1`
    raise "Command failed: #{result}" unless $?.success?
    result
  end

  # Initializes and creates a bare remote repo and a working repo with main branch
  def initialize
    @remote_dir = Dir.mktmpdir
    @remote_repo = File.join(@remote_dir, "origin.git")
    
    run_command("git init --bare #{@remote_repo}")
    
    Dir.chdir(@remote_repo) do
      `git symbolic-ref HEAD refs/heads/main`
    end
    
    @commits = []
    @work_dir = Dir.mktmpdir
    Dir.chdir(@work_dir) do
      run_command("git clone #{@remote_repo} .")
      run_command("git checkout -b main")
      FileUtils.mkdir_p("railties")
      File.write("railties/README", "keep")
      run_command("git add railties")

      run_command("git config user.email 'test@example.com'")
      run_command("git config user.name 'Test User'")

      commit_result = run_command("git commit -m 'add railties dir'")
      @commits << run_command("git rev-parse HEAD").strip
    end
  end

  def add_commit(message)
    Dir.chdir(@work_dir) do
      `git commit --allow-empty -n -m "#{message}" > /dev/null 2>&1`
      sha = `git rev-parse HEAD`.strip
      @commits << sha
      `git push origin main > /dev/null 2>&1`
      `git fetch origin main > /dev/null 2>&1`
    end

    @commits.last
  end

  def clone_at_commit(commit_sha, dest_path)
    `git clone #{@remote_repo} #{dest_path} > /dev/null 2>&1`
    Dir.chdir(dest_path) do
      `git checkout #{commit_sha} > /dev/null 2>&1`
      `git fetch origin main > /dev/null 2>&1`
    end
  end

  def cleanup
    Dir.chdir(@work_dir) do
      `git reset --hard main > /dev/null 2>&1`
      `git clean -fdx > /dev/null 2>&1`
    end
  end
end
