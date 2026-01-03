# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class Version < ActiveRecord::Base
        belongs_to :package, foreign_key: :package_purl, primary_key: :purl

        validates :purl, presence: true, uniqueness: true
        validates :package_purl, presence: true

        def parsed_purl
          @parsed_purl ||= Purl.parse(purl)
        end

        def version_string
          parsed_purl.version
        end

        def registry_url
          parsed_purl.registry_url
        end

        def enriched?
          enriched_at.present?
        end
      end
    end
  end
end
