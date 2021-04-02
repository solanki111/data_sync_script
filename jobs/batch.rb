# frozen_string_literal: true

require_relative '../clients/soap.rb'
require_relative '../clients/rest.rb'
require_relative '../helper/logging.rb'
require_relative '../helper/map_consents.rb'
require_relative '../helper/delete_consents.rb'

module Jobs
  # Public: Batch mode which does operations like addition, updatioon & deletion.
  class Batch
    include Logging
    include Clients::Soap
    include Clients::Rest
    include Helper::MapConsents
    include Helper::DeleteConsents

    # Public: Initialize logger in Batch mode
    #
    # Return: Void
    def initialize
      Logging.setup(Logger::INFO)
    end

    # Public: Run in Batch mode which includes opeartions like Additions, Updation and Deletions on
    #         HEL records and Addition on National records.
    #
    # Returns: Void
    def run
      # Process Starting Time
      starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Get all consent records from National service.
      all_nat_consents = national_consents_get

      # Get all consent records from HEL service.
      all_hel_consents = hel_records_get

      # Identify and add new consents records from both services
      mapping_all_new_consents(all_nat_consents[:assertions], all_hel_consents)

      # If CS records are present send to check for records which need to be deleted.
      if all_hel_consents.size.zero? || all_nat_consents[:assertions].size.zero?
        Logging.logger.info 'Delete process Aborted as no records retrieved either from HEL/CS or Inera/NS.'
      else
        del_hel_consents_recs(all_hel_consents, all_nat_consents)
      end

      # Process Ending Time and calculate total time taken for processing.
      ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Logging.logger.info "Time taken to run the job: #{format('%<time>0000.3f', time: (ending - starting))} sec"
    end

    # Public: Identify and delete records in HEL service by comparing alias Ids with records from
    #         cancelled assertions from National service.
    #
    # all_hel_records - All records from consent service
    # all_nat_consents - All valid & cancelled records from national service
    #
    # Returns: Void
    def del_hel_consents_recs(all_hel_consents, all_nat_consents)
      del_records_counter = 0
      all_hel_consents.each do |hel_recs|
        index = hel_recs[:aliases].find_index { |hel| hel[:system] == ENV['SYSTEM'] && hel[:value].present? }
        if index
          assertion_id = hel_recs[:aliases][index][:value]
          unless all_nat_consents[:assertions]&.any? { |nat| nat[:assertion_id] == assertion_id }
            del_records_counter += deleting_hel_consents(hel_recs) == 204 ? 1 : 0
          end
          if all_nat_consents[:cancelled]&.any? { |nat| nat[:assertion_id] == assertion_id }
            del_records_counter += deleting_hel_consents(hel_recs) == 204 ? 1 : 0
          end
        end
      end
      Logging.logger.info "CS records DELETED: #{del_records_counter}"
    end
  end
end
