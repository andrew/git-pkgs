# frozen_string_literal: true

require "test_helper"

class Git::Pkgs::TestColor < Minitest::Test
  def setup
    @original_env = {
      "NO_COLOR" => ENV["NO_COLOR"],
      "TERM" => ENV["TERM"]
    }
    Git::Pkgs::Color.reset!
  end

  def teardown
    @original_env.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
    Git::Pkgs::Color.reset!
  end

  def test_no_color_env_disables_color
    ENV["NO_COLOR"] = "1"
    Git::Pkgs::Color.reset!

    refute Git::Pkgs::Color.enabled?
  end

  def test_term_dumb_disables_color
    ENV.delete("NO_COLOR")
    ENV["TERM"] = "dumb"
    Git::Pkgs::Color.reset!

    refute Git::Pkgs::Color.enabled?
  end

  def test_colorize_returns_plain_text_when_disabled
    Git::Pkgs::Color.enabled = false

    assert_equal "hello", Git::Pkgs::Color.red("hello")
    assert_equal "world", Git::Pkgs::Color.green("world")
  end

  def test_colorize_returns_ansi_codes_when_enabled
    Git::Pkgs::Color.enabled = true

    assert_equal "\e[31mhello\e[0m", Git::Pkgs::Color.red("hello")
    assert_equal "\e[32mworld\e[0m", Git::Pkgs::Color.green("world")
    assert_equal "\e[33mtest\e[0m", Git::Pkgs::Color.yellow("test")
  end

  def test_normalize_color_value
    assert_equal "always", Git::Pkgs::Color.normalize_color_value("true")
    assert_equal "always", Git::Pkgs::Color.normalize_color_value("always")
    assert_equal "always", Git::Pkgs::Color.normalize_color_value("TRUE")
    assert_equal "never", Git::Pkgs::Color.normalize_color_value("false")
    assert_equal "never", Git::Pkgs::Color.normalize_color_value("never")
    assert_equal "never", Git::Pkgs::Color.normalize_color_value("FALSE")
    assert_equal "auto", Git::Pkgs::Color.normalize_color_value("auto")
    assert_equal "auto", Git::Pkgs::Color.normalize_color_value("anything")
  end
end
