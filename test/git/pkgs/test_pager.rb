# frozen_string_literal: true

require "test_helper"
require "stringio"

class Git::Pkgs::TestPager < Minitest::Test
  class PagerTestClass
    include Git::Pkgs::Pager

    attr_accessor :options

    def initialize(options = {})
      @options = options
    end
  end

  def setup
    @original_env = {
      "GIT_PAGER" => ENV["GIT_PAGER"],
      "PAGER" => ENV["PAGER"]
    }
    ENV.delete("GIT_PAGER")
    ENV.delete("PAGER")
  end

  def teardown
    @original_env.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end

  def test_git_pager_prefers_git_pager_env
    ENV["GIT_PAGER"] = "my-pager"
    ENV["PAGER"] = "other-pager"

    pager = PagerTestClass.new
    assert_equal "my-pager", pager.git_pager
  end

  def test_git_pager_falls_back_to_pager_env
    ENV.delete("GIT_PAGER")
    ENV["PAGER"] = "other-pager"

    pager = PagerTestClass.new

    # Stub git config to return empty
    pager.define_singleton_method(:`) do |cmd|
      cmd.include?("git config") ? "" : super(cmd)
    end

    assert_equal "other-pager", pager.git_pager
  end

  def test_git_pager_defaults_to_less
    ENV.delete("GIT_PAGER")
    ENV.delete("PAGER")

    pager = PagerTestClass.new

    # Stub git config to return empty
    pager.define_singleton_method(:`) do |cmd|
      cmd.include?("git config") ? "" : super(cmd)
    end

    assert_equal "less -FRSX", pager.git_pager
  end

  def test_git_pager_ignores_empty_git_pager_env
    ENV["GIT_PAGER"] = ""
    ENV["PAGER"] = "other-pager"

    pager = PagerTestClass.new

    # Stub git config to return empty
    pager.define_singleton_method(:`) do |cmd|
      cmd.include?("git config") ? "" : super(cmd)
    end

    assert_equal "other-pager", pager.git_pager
  end

  def test_pager_disabled_when_empty
    pager = PagerTestClass.new
    pager.define_singleton_method(:git_pager) { "" }

    assert pager.pager_disabled?
  end

  def test_pager_disabled_when_cat
    pager = PagerTestClass.new
    pager.define_singleton_method(:git_pager) { "cat" }

    assert pager.pager_disabled?
  end

  def test_pager_not_disabled_for_less
    pager = PagerTestClass.new
    pager.define_singleton_method(:git_pager) { "less" }

    refute pager.pager_disabled?
  end

  def test_paging_disabled_via_option
    pager = PagerTestClass.new(no_pager: true)

    assert pager.paging_disabled?
  end

  def test_paging_not_disabled_without_option
    pager = PagerTestClass.new(no_pager: false)

    refute pager.paging_disabled?
  end

  def test_paginate_outputs_directly_when_not_tty
    pager = PagerTestClass.new
    output = StringIO.new
    original_stdout = $stdout

    begin
      $stdout = output
      pager.paginate { puts "test output" }
    ensure
      $stdout = original_stdout
    end

    assert_equal "test output\n", output.string
  end

  def test_paginate_outputs_directly_when_pager_disabled
    pager = PagerTestClass.new(no_pager: true)
    output = StringIO.new
    original_stdout = $stdout

    begin
      $stdout = output
      pager.paginate { puts "test output" }
    ensure
      $stdout = original_stdout
    end

    assert_equal "test output\n", output.string
  end

  def test_paginate_outputs_directly_when_pager_is_cat
    pager = PagerTestClass.new
    pager.define_singleton_method(:git_pager) { "cat" }
    output = StringIO.new
    original_stdout = $stdout

    begin
      $stdout = output
      pager.paginate { puts "test output" }
    ensure
      $stdout = original_stdout
    end

    assert_equal "test output\n", output.string
  end
end
