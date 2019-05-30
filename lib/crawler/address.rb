require 'active_support/core_ext/hash/keys'
require 'active_support/inflector'
require 'crawler/base'
require 'crawler/utils'

module Crawler
  module Address
    include Base

    PROVIDERS = {}
    SCORES = {}

    def self.add_provider(provider_name, options = {})
      options.assert_valid_keys :score, :insert_at, :country, :countries

      countries = options[:countries] || []
      countries += [options[:country].to_s || 'all'] if countries.empty?

      countries.each do |country|
        PROVIDERS[country] ||= []
        PROVIDERS[country].insert(options[:insert_at] || -1, provider_name)
      end

      if (score = options[:score])
        SCORES[provider_name] = score
      end
    end

    def self.search(street, zipcode, city, country)
      providers = PROVIDERS['all'] || []
      providers += PROVIDERS[country.to_s] || []

      addresses = providers.flat_map do |provider_name|
        camelized = ActiveSupport::Inflector.camelize("crawler/address/providers/#{provider_name.to_s}")
        klass = ActiveSupport::Inflector.constantize(camelized)
        addresses = klass.resolve(street, zipcode, city, country)

        addresses.map do |address|
          provider_score = SCORES[provider_name] || 0.5
          street_score = Utils.levenshtein_score(street, address[:street])
          zipcode_score = zipcode.to_s == address[:zipcode].to_s ? 1.0 : 0.9
          city_score = Utils.levenshtein_score(city, address[:city])

          {
            data: address,
            score: provider_score * street_score * zipcode_score * city_score
          }
        end
      end

      addresses.group_by do |address|
        [Utils.transliterate(address[:data][:street]), Utils.transliterate(address[:data][:zipcode]), Utils.transliterate(address[:data][:city])]
      end
    end

    def self.best(street, zipcode, city, country)
      data = search(street, zipcode, city, country).max_by do |_, addresses|
        address = addresses.max_by do |address|
          address[:score]
        end

        address[:score]
      end

      data&.last
    end
  end
end
