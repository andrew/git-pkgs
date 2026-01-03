# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class Package < ActiveRecord::Base
        has_many :versions, foreign_key: :package_purl, primary_key: :purl

        validates :purl, presence: true, uniqueness: true

        def parsed_purl
          @parsed_purl ||= Purl.parse(purl)
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
