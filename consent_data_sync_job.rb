# frozen_string_literal: true

require_relative 'jobs/batch.rb'
require_relative 'helper/logging.rb'
require_relative 'jobs/incremental.rb'
require_relative 'clients/services.rb'

# Script job to sync consents records between National/Inera & Consent/HealtheIntent service.
module DataSyncJob
  include Logging

  # Initialize logger
  Logging.setup(Logger::INFO)

  unless %w[batch incremental].include?(ENV['MODE'])
    raise ArgumentError,
          "Invalid Mode passed: '#{ENV['MODE']}'. It should be either 'batch' or 'incremental'!"
  end

  unless %w[development production staging test].include?(ENV['DOMAIN'])
    raise ArgumentError,
          "Invalid Domain type passed: '#{ENV['DOMAIN']}'. "\
          'It should be \'dev\', \'staging\' \'prod\' or \'test\'!'
  end

  begin
    env_configs = YAML
                  .safe_load(ERB.new(File.read('./config/configs.yml')).result, [], [], true)[ENV['DOMAIN']]
                  .with_indifferent_access
    ENV['POP_ID'] = env_configs[:population]
    ENV['SYSTEM'] = env_configs[:system]
  rescue Errno::ENOENT => e
    Logging.logger.error "Population_ID File or directory doesn't exist. #{e.inspect}"
    raise Errno::ENOENT, 'Population_ID File or directory doesnt exist!'
  rescue Errno::EACCES => e
    Logging.logger.error "Cannot read Population_ID file! #{e.inspect}"
    raise Errno::EACCES, 'Can\'t read Population_ID file!'
  rescue NoMethodError => e
    Logging.logger.error "Configs not found in Population_ID file! #{e.inspect}"
    raise NoMethodError, 'Configs not found in Population_ID file!'
  end

  # Calling the appropriate Job mode to run
  Logging.logger.info "------- #{ENV['MODE'].capitalize} job started for #{ENV['DOMAIN'].capitalize}  -------"

  if ENV['MODE'] == 'batch'
    Jobs::Batch.new.run
  elsif ENV['MODE'] == 'incremental'
    Jobs::Incremental.new.run
  end
end
