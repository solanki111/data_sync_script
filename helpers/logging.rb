# frozen_string_literal: true

require 'logger'
require 'cerner/timber'

# Module for including logging into any class.
module Logging
  # Public: Reader for the logger instance.
  #
  # Returns a Logger instance.
  #
  # Raises StandardError if logger has not been initialized.
  def self.logger
    raise StandardError, 'logger has not been initialized' unless @logger

    @logger
  end

  # Public: Sets up logger instance with the given logger level.
  #
  # logger_level - Logger level to be used for initialization. Ex: Logger::INFO, Logger::DEBUG
  #
  # Returns a Logger instance.
  def self.setup(logger_level)
    @logger = Logger.new(STDOUT)
    @logger.level = logger_level
    @logger.formatter = Cerner::Timber::LoggerFormatter.new
    @logger
  end
end
