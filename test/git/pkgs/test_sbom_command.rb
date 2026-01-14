# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class Git::Pkgs::TestSbomCommand < Minitest::Test
  include TestHelpers

  def setup
    create_test_repo
    add_file("README.md", "# Test")
    commit("Initial commit")

    @git_dir = File.join(@test_dir, ".git")
    WebMock.disable_net_connect!
  end

  def teardown
    cleanup_test_repo
    WebMock.allow_net_connect!
  end

  def test_sbom_spdx_json_output
    add_file("package-lock.json", <<~JSON)
      {
        "name": "test-project",
        "lockfileVersion": 2,
        "packages": {
          "node_modules/lodash": {
            "version": "4.17.21"
          },
          "node_modules/express": {
            "version": "4.18.0"
          }
        }
      }
    JSON
    commit("Add package-lock.json")

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Sbom.new(["--stateless", "--skip-enrichment", "--type", "spdx"]).run
      end.first
    end

    json = JSON.parse(output)
    assert_equal "SPDX-2.3", json["spdxVersion"]
    assert json["packages"]
    assert_equal 2, json["packages"].size

    lodash = json["packages"].find { |p| p["name"] == "lodash" }
    assert lodash
    assert_equal "4.17.21", lodash["versionInfo"]
    assert lodash["externalRefs"].any? { |r| r["referenceLocator"] == "pkg:npm/lodash@4.17.21" }
  end

  def test_sbom_cyclonedx_json_output
    add_file("package-lock.json", <<~JSON)
      {
        "name": "test-project",
        "lockfileVersion": 2,
        "packages": {
          "node_modules/lodash": {
            "version": "4.17.21"
          }
        }
      }
    JSON
    commit("Add package-lock.json")

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Sbom.new(["--stateless", "--skip-enrichment", "--type", "cyclonedx"]).run
      end.first
    end

    json = JSON.parse(output)
    assert_equal "CycloneDX", json["bomFormat"]
    assert json["components"]
    assert_equal 1, json["components"].size

    lodash = json["components"].find { |c| c["name"] == "lodash" }
    assert lodash
    assert_equal "4.17.21", lodash["version"]
    assert_equal "pkg:npm/lodash@4.17.21", lodash["purl"]
  end

  def test_sbom_with_custom_project_name
    add_file("Gemfile.lock", <<~LOCK)
      GEM
        specs:
          rake (13.0.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake
    LOCK
    commit("Add Gemfile.lock")

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Sbom.new(["--stateless", "--skip-enrichment", "--name", "my-project", "--type", "spdx"]).run
      end.first
    end

    json = JSON.parse(output)
    assert_equal "my-project", json["name"]
  end

  def test_sbom_with_enrichment
    add_file("package-lock.json", <<~JSON)
      {
        "name": "test-project",
        "lockfileVersion": 2,
        "packages": {
          "node_modules/lodash": {
            "version": "4.17.21"
          }
        }
      }
    JSON
    commit("Add package-lock.json")

    stub_request(:post, "https://packages.ecosyste.ms/api/v1/packages/bulk_lookup")
      .to_return(
        status: 200,
        body: [{ "purl" => "pkg:npm/lodash", "normalized_licenses" => ["MIT"] }].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://packages.ecosyste.ms/api/v1/registries/npmjs.org/packages/lodash/versions/4.17.21")
      .to_return(
        status: 200,
        body: { "licenses" => ["MIT"], "integrity" => "sha512-abc123" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Sbom.new(["--stateless"]).run
      end.first
    end

    json = JSON.parse(output)
    lodash = json["components"].find { |c| c["name"] == "lodash" }
    assert lodash
    assert lodash["licenses"]
  end

  def test_sbom_with_supplier_info
    add_file("package-lock.json", <<~JSON)
      {
        "name": "test-project",
        "lockfileVersion": 2,
        "packages": {
          "node_modules/lodash": {
            "version": "4.17.21"
          }
        }
      }
    JSON
    commit("Add package-lock.json")

    stub_request(:post, "https://packages.ecosyste.ms/api/v1/packages/bulk_lookup")
      .to_return(
        status: 200,
        body: [{
          "purl" => "pkg:npm/lodash",
          "normalized_licenses" => ["MIT"],
          "owner_record" => { "name" => "lodash", "kind" => "organization" }
        }].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://packages.ecosyste.ms/api/v1/registries/npmjs.org/packages/lodash/versions/4.17.21")
      .to_return(status: 404)

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Sbom.new(["--stateless"]).run
      end.first
    end

    json = JSON.parse(output)
    lodash = json["components"].find { |c| c["name"] == "lodash" }
    assert lodash
    assert_equal "lodash", lodash["supplier"]["name"]
  end

  def test_sbom_ecosystem_filter
    add_file("package-lock.json", <<~JSON)
      {
        "name": "test-project",
        "lockfileVersion": 2,
        "packages": {
          "node_modules/lodash": {
            "version": "4.17.21"
          }
        }
      }
    JSON
    add_file("Gemfile.lock", <<~LOCK)
      GEM
        specs:
          rake (13.0.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake
    LOCK
    commit("Add lockfiles")

    output = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Sbom.new(["--stateless", "--skip-enrichment", "--ecosystem", "npm"]).run
      end.first
    end

    json = JSON.parse(output)
    assert_equal 1, json["components"].size
    assert_equal "lodash", json["components"].first["name"]
  end

  def test_sbom_no_dependencies
    output, = Dir.chdir(@test_dir) do
      capture_io do
        Git::Pkgs::Commands::Sbom.new(["--stateless", "--skip-enrichment"]).run
      end
    end

    assert_match(/No dependencies found/, output)
  end

  def test_parse_integrity_sha256
    cmd = Git::Pkgs::Commands::Sbom.new([])

    assert_equal ["SHA256", "abc123"], cmd.parse_integrity("sha256-abc123")
    assert_equal ["SHA256", "abc123"], cmd.parse_integrity("sha256:abc123")
    assert_equal ["SHA256", "abc123"], cmd.parse_integrity("sha256=abc123")
  end

  def test_parse_integrity_sha512
    cmd = Git::Pkgs::Commands::Sbom.new([])

    assert_equal ["SHA512", "xyz789"], cmd.parse_integrity("sha512-xyz789")
    assert_equal ["SHA512", "xyz789"], cmd.parse_integrity("sha512:xyz789")
  end

  def test_parse_integrity_unknown_format
    cmd = Git::Pkgs::Commands::Sbom.new([])

    assert_nil cmd.parse_integrity("unknown-format")
    assert_nil cmd.parse_integrity(nil)
  end

  def test_parse_integrity_go_h1_format
    cmd = Git::Pkgs::Commands::Sbom.new([])

    # Go's h1: format is base64-encoded SHA256, needs conversion to hex
    result = cmd.parse_integrity("h1:FEBLx1zS214owpjy7qsBeixbURkuhQAwrK5UwLGTwt4=")
    assert_equal "SHA256", result[0]
    # Verify it's a valid 64-char hex string (SHA256)
    assert_match(/\A[0-9a-f]{64}\z/, result[1])
  end

end
