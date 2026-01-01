# frozen_string_literal: true

require "test_helper"

class Git::Pkgs::TestAnalyzer < Minitest::Test
  include TestHelpers

  def setup
    create_test_repo
    add_file("README.md", "# Test")
    commit("Initial commit")
  end

  def teardown
    cleanup_test_repo
  end

  def test_analyze_commit_with_no_manifests
    repo = Git::Pkgs::Repository.new(@test_dir)
    analyzer = Git::Pkgs::Analyzer.new(repo)

    first_commit = repo.walk("main").first
    result = analyzer.analyze_commit(first_commit)

    assert_nil result
  end

  def test_analyze_commit_with_added_gemfile
    add_file("Gemfile", sample_gemfile("rails" => "~> 7.0", "puma" => "~> 6.0"))
    commit("Add Gemfile")

    repo = Git::Pkgs::Repository.new(@test_dir)
    analyzer = Git::Pkgs::Analyzer.new(repo)

    commits = repo.walk("main").to_a
    second_commit = commits[1]
    result = analyzer.analyze_commit(second_commit)

    refute_nil result
    assert_equal 2, result[:changes].size

    rails_change = result[:changes].find { |c| c[:name] == "rails" }
    assert_equal "added", rails_change[:change_type]
    assert_equal "~> 7.0", rails_change[:requirement]
    assert_equal "rubygems", rails_change[:ecosystem]
  end

  def test_analyze_commit_with_modified_gemfile
    add_file("Gemfile", sample_gemfile("rails" => "~> 7.0"))
    commit("Add Gemfile")

    add_file("Gemfile", sample_gemfile("rails" => "~> 7.1"))
    commit("Update rails")

    repo = Git::Pkgs::Repository.new(@test_dir)
    analyzer = Git::Pkgs::Analyzer.new(repo)

    commits = repo.walk("main").to_a
    third_commit = commits[2]

    # Build snapshot from previous commit
    second_commit = commits[1]
    prev_result = analyzer.analyze_commit(second_commit)

    result = analyzer.analyze_commit(third_commit, prev_result[:snapshot])

    refute_nil result
    assert_equal 1, result[:changes].size

    rails_change = result[:changes].first
    assert_equal "modified", rails_change[:change_type]
    assert_equal "~> 7.0", rails_change[:previous_requirement]
    assert_equal "~> 7.1", rails_change[:requirement]
  end

  def test_analyze_commit_with_removed_dependency
    add_file("Gemfile", sample_gemfile("rails" => "~> 7.0", "puma" => "~> 6.0"))
    commit("Add Gemfile")

    add_file("Gemfile", sample_gemfile("rails" => "~> 7.0"))
    commit("Remove puma")

    repo = Git::Pkgs::Repository.new(@test_dir)
    analyzer = Git::Pkgs::Analyzer.new(repo)

    commits = repo.walk("main").to_a

    second_commit = commits[1]
    prev_result = analyzer.analyze_commit(second_commit)

    third_commit = commits[2]
    result = analyzer.analyze_commit(third_commit, prev_result[:snapshot])

    refute_nil result
    assert_equal 1, result[:changes].size

    puma_change = result[:changes].first
    assert_equal "removed", puma_change[:change_type]
    assert_equal "puma", puma_change[:name]
  end

  def test_skips_merge_commits
    # Create a simple repo - merge commit detection works on parent count
    repo = Git::Pkgs::Repository.new(@test_dir)
    first_commit = repo.walk("main").first
    # Manually check that merge detection works
    refute repo.merge_commit?(first_commit)
  end
end
