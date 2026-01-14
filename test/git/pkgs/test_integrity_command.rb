# frozen_string_literal: true

require "test_helper"

class Git::Pkgs::TestIntegrityCommand < Minitest::Test
  include TestHelpers

  def setup
    create_test_repo
    add_file("README.md", "# Test")
    commit("Initial commit")
  end

  def teardown
    cleanup_test_repo
  end

  def test_integrity_shows_hashes_stateless
    lockfile = <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.0.6)
          minitest (5.18.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake
        minitest

      CHECKSUMS
        rake (13.0.6) sha256=7854c74f48e2e975969062833adc4013f249a4b212f5e7b9d5c040bf838d54bb
        minitest (5.18.0) sha256=abc123def456

      BUNDLED WITH
         2.4.0
    LOCKFILE

    add_file("Gemfile.lock", lockfile)
    commit("Add Gemfile.lock")

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Integrity.new(["--stateless"]).run
      end.first
    end

    assert_includes output, "rake"
    assert_includes output, "sha256=7854c74f48e2e975969062833adc4013f249a4b212f5e7b9d5c040bf838d54bb"
    assert_includes output, "minitest"
    assert_includes output, "sha256=abc123def456"
  end

  def test_integrity_json_format
    lockfile = <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.0.6)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake

      CHECKSUMS
        rake (13.0.6) sha256=7854c74f48e2e975969062833adc4013f249a4b212f5e7b9d5c040bf838d54bb

      BUNDLED WITH
         2.4.0
    LOCKFILE

    add_file("Gemfile.lock", lockfile)
    commit("Add Gemfile.lock")

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Integrity.new(["--stateless", "-f", "json"]).run
      end.first
    end

    result = JSON.parse(output)
    assert_equal 1, result.size
    assert_equal "rake", result[0]["name"]
    assert_equal "sha256=7854c74f48e2e975969062833adc4013f249a4b212f5e7b9d5c040bf838d54bb", result[0]["integrity"]
  end

  def test_integrity_empty_when_no_checksums
    add_file("Gemfile", sample_gemfile("rails" => "~> 7.0"))
    commit("Add Gemfile")

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Integrity.new(["--stateless"]).run
      end.first
    end

    assert_includes output, "No dependencies with integrity hashes found"
  end

  def test_integrity_ecosystem_filter
    lockfile = <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.0.6)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake

      CHECKSUMS
        rake (13.0.6) sha256=7854c74f48e2e975969062833adc4013f249a4b212f5e7b9d5c040bf838d54bb

      BUNDLED WITH
         2.4.0
    LOCKFILE

    add_file("Gemfile.lock", lockfile)
    commit("Add Gemfile.lock")

    # Filter by ecosystem that doesn't exist
    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Integrity.new(["--stateless", "-e", "npm"]).run
      end.first
    end

    assert_includes output, "No dependencies with integrity hashes found"

    # Filter by correct ecosystem
    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Integrity.new(["--stateless", "-e", "rubygems"]).run
      end.first
    end

    assert_includes output, "rake"
  end
end
