# frozen_string_literal: true

require_relative '../clients/soap.rb'
require_relative '../clients/rest.rb'
require_relative '../helper/logging.rb'
require_relative '../helper/map_consents.rb'

module Jobs
  # Public: Incremental mode which does opeartions like addition & updation.
  class Incremental
    include Logging
    include Clients::Soap
    include Clients::Rest
    include Helper::MapConsents

    # Public: Initialize logger in Incremental mode
    #
    # Return: Void
    def initialize
      Logging.setup(Logger::INFO)
    end

    # Public: Run in Incremental mode which only includes opeartions like Additions to both services.
    #
    # Returns: Void
    def run
      # Process Starting Time
      starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Get records from national service. They'll be fetched from a certain time onwards.
      new_nat_assertions = national_consents_get

      # Get new consent records from HEL service.
      new_hel_consents = hel_records_get

      # Identify and add new records
      mapping_all_new_consents(new_nat_assertions[:assertions], new_hel_consents)

      # Process Ending Time and calculate total time taken for processing.
      ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Logging.logger.info "Time taken to run the job: #{format('%<time>0000.3f', time: (ending - starting))}sec"
    end
  end
end
