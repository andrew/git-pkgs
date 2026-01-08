# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "digest"
require "open-uri"

Minitest::TestTask.create do |t|
  t.test_prelude = 'require "test_helper"'
end

task default: :test

desc "Update Formula sha256 hash for current version"
task :update_formula do
  require_relative "lib/git/pkgs/version"
  version = Git::Pkgs::VERSION
  url = "https://github.com/andrew/git-pkgs/archive/refs/tags/v#{version}.tar.gz"

  puts "Downloading #{url}..."
  tarball = URI.open(url).read
  sha256 = Digest::SHA256.hexdigest(tarball)
  puts "SHA256: #{sha256}"

  formula_path = "Formula/git-pkgs.rb"
  formula = File.read(formula_path)
  formula.gsub!(/url ".*"/, "url \"#{url}\"")
  formula.gsub!(/sha256 ".*"/, "sha256 \"#{sha256}\"")
  File.write(formula_path, formula)
  puts "Updated #{formula_path}"
end

Rake::Task["release"].enhance do
  Rake::Task["update_formula"].invoke
end
