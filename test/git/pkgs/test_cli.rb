# frozen_string_literal: true

require "test_helper"
require "stringio"

class Git::Pkgs::TestCLI < Minitest::Test
  include TestHelpers

  def test_help_command
    output = capture_stdout do
      Git::Pkgs::CLI.run(["help"])
    end

    assert_includes output, "Usage: git pkgs"
    assert_includes output, "init"
    assert_includes output, "list"
    assert_includes output, "history"
  end

  def test_version_command
    output = capture_stdout do
      Git::Pkgs::CLI.run(["--version"])
    end

    assert_includes output, Git::Pkgs::VERSION
  end

  def test_unknown_command_exits_with_error
    assert_raises(SystemExit) do
      capture_stderr do
        Git::Pkgs::CLI.run(["unknown"])
      end
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end
end

class Git::Pkgs::TestDiffCommand < Minitest::Test
  include TestHelpers

  def setup
    create_test_repo
    add_file("Gemfile", "source 'https://rubygems.org'\ngem 'rails'")
    commit("Initial commit")
    add_file("Gemfile", "source 'https://rubygems.org'\ngem 'rails'\ngem 'puma'")
    commit("Add puma")
    @git_dir = File.join(@test_dir, ".git")
    Git::Pkgs::Database.connect(@git_dir)
    Git::Pkgs::Database.create_schema
  end

  def teardown
    cleanup_test_repo
  end

  def test_find_or_create_commit_finds_existing_commit
    repo = Git::Pkgs::Repository.new(@test_dir)
    sha = repo.head_sha

    # Create commit in database first
    Git::Pkgs::Models::Commit.create!(
      sha: sha,
      message: "Test",
      author_name: "Test",
      author_email: "test@example.com",
      committed_at: Time.now
    )

    diff = Git::Pkgs::Commands::Diff.new([])
    result = diff.send(:find_or_create_commit, repo, sha)

    assert result
    assert_equal sha, result.sha
  end

  def test_find_or_create_commit_creates_missing_commit
    repo = Git::Pkgs::Repository.new(@test_dir)
    sha = repo.head_sha

    # Commit doesn't exist in database yet
    assert_nil Git::Pkgs::Models::Commit.find_by(sha: sha)

    diff = Git::Pkgs::Commands::Diff.new([])
    result = diff.send(:find_or_create_commit, repo, sha)

    assert result
    assert_equal sha, result.sha
    # Verify it was persisted
    assert Git::Pkgs::Models::Commit.find_by(sha: sha)
  end

  def test_find_or_create_commit_returns_nil_for_invalid_sha
    repo = Git::Pkgs::Repository.new(@test_dir)

    diff = Git::Pkgs::Commands::Diff.new([])
    result = diff.send(:find_or_create_commit, repo, "0000000000000000000000000000000000000000")

    assert_nil result
  end
end

class Git::Pkgs::TestShowCommand < Minitest::Test
  include TestHelpers

  def setup
    create_test_repo
    add_file("Gemfile", "source 'https://rubygems.org'\ngem 'rails'")
    commit("Add rails")
    @first_sha = get_head_sha
    add_file("Gemfile", "source 'https://rubygems.org'\ngem 'rails'\ngem 'puma'")
    commit("Add puma")
    @second_sha = get_head_sha
    @git_dir = File.join(@test_dir, ".git")
    Git::Pkgs::Database.connect(@git_dir)
    Git::Pkgs::Database.create_schema
  end

  def teardown
    cleanup_test_repo
  end

  def test_show_displays_changes_for_commit
    create_commit_with_changes(@second_sha, [
      { name: "puma", change_type: "added", requirement: ">= 0" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Show.new([@second_sha]).run
      end
    end

    assert_includes output, "puma"
    assert_includes output, "Added:"
  end

  def test_show_defaults_to_head
    create_commit_with_changes(@second_sha, [
      { name: "puma", change_type: "added", requirement: ">= 0" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Show.new([]).run
      end
    end

    assert_includes output, "puma"
  end

  def test_show_no_changes_message
    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Show.new([@first_sha]).run
      end
    end

    assert_includes output, "No dependency changes"
  end

  def test_show_json_format
    create_commit_with_changes(@second_sha, [
      { name: "puma", change_type: "added", requirement: ">= 0" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Show.new(["--format=json"]).run
      end
    end

    data = JSON.parse(output)
    assert_equal 1, data["changes"].length
    assert_equal "puma", data["changes"].first["name"]
  end

  def test_show_filters_by_ecosystem
    create_commit_with_changes(@second_sha, [
      { name: "puma", change_type: "added", requirement: ">= 0", ecosystem: "rubygems" },
      { name: "express", change_type: "added", requirement: "^4.0", ecosystem: "npm" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Show.new(["--ecosystem=rubygems"]).run
      end
    end

    assert_includes output, "puma"
    refute_includes output, "express"
  end

  def get_head_sha
    Dir.chdir(@test_dir) do
      `git rev-parse HEAD`.strip
    end
  end

  def create_commit_with_changes(sha, changes)
    commit = Git::Pkgs::Models::Commit.create!(
      sha: sha,
      message: "Test commit",
      author_name: "Test User",
      author_email: "test@example.com",
      committed_at: Time.now,
      has_dependency_changes: true
    )

    manifest = Git::Pkgs::Models::Manifest.create!(
      path: "Gemfile",
      ecosystem: "rubygems",
      kind: "manifest"
    )

    changes.each do |change|
      Git::Pkgs::Models::DependencyChange.create!(
        commit: commit,
        manifest: manifest,
        name: change[:name],
        change_type: change[:change_type],
        requirement: change[:requirement],
        ecosystem: change[:ecosystem] || "rubygems",
        dependency_type: "runtime"
      )
    end

    commit
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

class Git::Pkgs::TestHistoryCommand < Minitest::Test
  include TestHelpers

  def setup
    create_test_repo
    add_file("Gemfile", "source 'https://rubygems.org'\ngem 'rails'")
    commit("Add rails")
    @git_dir = File.join(@test_dir, ".git")
    Git::Pkgs::Database.connect(@git_dir)
    Git::Pkgs::Database.create_schema
  end

  def teardown
    cleanup_test_repo
  end

  def test_history_filters_by_author
    create_commit_with_author("alice", "alice@example.com", [
      { name: "rails", change_type: "added", requirement: ">= 0" }
    ])
    create_commit_with_author("bob", "bob@example.com", [
      { name: "puma", change_type: "added", requirement: ">= 0" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::History.new(["--author=alice"]).run
      end
    end

    assert_includes output, "rails"
    refute_includes output, "puma"
  end

  def test_history_filters_by_author_email
    create_commit_with_author("alice", "alice@example.com", [
      { name: "rails", change_type: "added", requirement: ">= 0" }
    ])
    create_commit_with_author("bob", "bob@example.com", [
      { name: "puma", change_type: "added", requirement: ">= 0" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::History.new(["--author=bob@example"]).run
      end
    end

    refute_includes output, "rails"
    assert_includes output, "puma"
  end

  def test_history_filters_by_since
    create_commit_at(Time.new(2024, 1, 1), [
      { name: "rails", change_type: "added", requirement: ">= 0" }
    ])
    create_commit_at(Time.new(2024, 6, 1), [
      { name: "puma", change_type: "added", requirement: ">= 0" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::History.new(["--since=2024-03-01"]).run
      end
    end

    refute_includes output, "rails"
    assert_includes output, "puma"
  end

  def test_history_filters_by_until
    create_commit_at(Time.new(2024, 1, 1), [
      { name: "rails", change_type: "added", requirement: ">= 0" }
    ])
    create_commit_at(Time.new(2024, 6, 1), [
      { name: "puma", change_type: "added", requirement: ">= 0" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::History.new(["--until=2024-03-01"]).run
      end
    end

    assert_includes output, "rails"
    refute_includes output, "puma"
  end

  def test_history_filters_by_date_range
    create_commit_at(Time.new(2024, 1, 1), [
      { name: "rails", change_type: "added", requirement: ">= 0" }
    ])
    create_commit_at(Time.new(2024, 6, 1), [
      { name: "puma", change_type: "added", requirement: ">= 0" }
    ])
    create_commit_at(Time.new(2024, 12, 1), [
      { name: "sidekiq", change_type: "added", requirement: ">= 0" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::History.new(["--since=2024-03-01", "--until=2024-09-01"]).run
      end
    end

    refute_includes output, "rails"
    assert_includes output, "puma"
    refute_includes output, "sidekiq"
  end

  def create_commit_with_author(name, email, changes)
    sha = SecureRandom.hex(20)
    commit = Git::Pkgs::Models::Commit.create!(
      sha: sha,
      message: "Test commit",
      author_name: name,
      author_email: email,
      committed_at: Time.now,
      has_dependency_changes: true
    )

    manifest = Git::Pkgs::Models::Manifest.find_or_create_by!(
      path: "Gemfile",
      ecosystem: "rubygems",
      kind: "manifest"
    )

    changes.each do |change|
      Git::Pkgs::Models::DependencyChange.create!(
        commit: commit,
        manifest: manifest,
        name: change[:name],
        change_type: change[:change_type],
        requirement: change[:requirement],
        ecosystem: "rubygems",
        dependency_type: "runtime"
      )
    end

    commit
  end

  def create_commit_at(time, changes)
    sha = SecureRandom.hex(20)
    commit = Git::Pkgs::Models::Commit.create!(
      sha: sha,
      message: "Test commit",
      author_name: "Test User",
      author_email: "test@example.com",
      committed_at: time,
      has_dependency_changes: true
    )

    manifest = Git::Pkgs::Models::Manifest.find_or_create_by!(
      path: "Gemfile",
      ecosystem: "rubygems",
      kind: "manifest"
    )

    changes.each do |change|
      Git::Pkgs::Models::DependencyChange.create!(
        commit: commit,
        manifest: manifest,
        name: change[:name],
        change_type: change[:change_type],
        requirement: change[:requirement],
        ecosystem: "rubygems",
        dependency_type: "runtime"
      )
    end

    commit
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

class Git::Pkgs::TestStatsCommand < Minitest::Test
  include TestHelpers

  def setup
    create_test_repo
    add_file("Gemfile", "source 'https://rubygems.org'\ngem 'rails'")
    commit("Add rails")
    @git_dir = File.join(@test_dir, ".git")
    Git::Pkgs::Database.connect(@git_dir)
    Git::Pkgs::Database.create_schema
  end

  def teardown
    cleanup_test_repo
  end

  def test_stats_by_author_shows_counts
    create_commit_with_author("alice", "alice@example.com", [
      { name: "rails", change_type: "added" },
      { name: "puma", change_type: "added" }
    ])
    create_commit_with_author("bob", "bob@example.com", [
      { name: "sidekiq", change_type: "added" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Stats.new(["--by-author"]).run
      end
    end

    assert_includes output, "alice"
    assert_includes output, "bob"
    assert_includes output, "2"  # alice's count
  end

  def test_stats_by_author_only_counts_added
    create_commit_with_author("alice", "alice@example.com", [
      { name: "rails", change_type: "added" },
      { name: "puma", change_type: "modified" },
      { name: "sidekiq", change_type: "removed" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Stats.new(["--by-author"]).run
      end
    end

    assert_includes output, "alice"
    assert_includes output, "1"  # only the added one
  end

  def test_stats_by_author_json_format
    create_commit_with_author("alice", "alice@example.com", [
      { name: "rails", change_type: "added" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Stats.new(["--by-author", "--format=json"]).run
      end
    end

    data = JSON.parse(output)
    assert_equal 1, data.length
    assert_equal "alice", data.first["author"]
    assert_equal 1, data.first["added"]
  end

  def test_stats_by_author_respects_limit
    create_commit_with_author("alice", "alice@example.com", [
      { name: "rails", change_type: "added" }
    ])
    create_commit_with_author("bob", "bob@example.com", [
      { name: "puma", change_type: "added" }
    ])
    create_commit_with_author("charlie", "charlie@example.com", [
      { name: "sidekiq", change_type: "added" }
    ])

    output = capture_stdout do
      Dir.chdir(@test_dir) do
        Git::Pkgs::Commands::Stats.new(["--by-author", "-n", "2"]).run
      end
    end

    lines = output.lines.select { |l| l.match?(/^\s+\d+\s+\w/) }
    assert_equal 2, lines.length
  end

  def create_commit_with_author(name, email, changes)
    sha = SecureRandom.hex(20)
    commit = Git::Pkgs::Models::Commit.create!(
      sha: sha,
      message: "Test commit",
      author_name: name,
      author_email: email,
      committed_at: Time.now,
      has_dependency_changes: true
    )

    manifest = Git::Pkgs::Models::Manifest.find_or_create_by!(
      path: "Gemfile",
      ecosystem: "rubygems",
      kind: "manifest"
    )

    changes.each do |change|
      Git::Pkgs::Models::DependencyChange.create!(
        commit: commit,
        manifest: manifest,
        name: change[:name],
        change_type: change[:change_type],
        requirement: ">= 0",
        ecosystem: "rubygems",
        dependency_type: "runtime"
      )
    end

    commit
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
