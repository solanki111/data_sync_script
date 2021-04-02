# frozen_string_literal: true

require 'securerandom'
require_relative '../clients/soap.rb'
require_relative '../clients/rest.rb'
require_relative '../helper/logging.rb'
require_relative '../helper/add_consents.rb'
require_relative '../helper/update_consents.rb'

module Helper
  # Public: Mapping schema of the records for respective services accordingly.
  module MapConsents
    include Logging
    include Clients::Soap
    include Clients::Rest
    include Helper::AddConsents
    include Helper::UpdateConsents

    # Initialize logger
    Logging.setup(Logger::INFO)

    # Public: Fetching records from national service based on the message supplied.
    #
    # message - Contains the config value based on the retrieval type.
    #
    # Returns: sends the (multiple) response(s) stored in a array from the Inera ser to mapping_national_assertions
    #
    # Throws Exception: If the soap response or the service call encounters any type of error or is invalid.
    def national_consents_get
      nat_consents = { assertions: [], cancelled: [] }
      owner_id = owner_id_get
      mnemonic = tenants_mnemonic_get(owner_id)
      care_providers_ids = org_classes_get(mnemonic)
      Logging.logger.info "Care Providers retrieved: #{care_providers_ids.size}"

      care_providers_ids.each do |care_id|
        message = message_get(care_id, nil)
        next if message.nil?

        conn = national_consent_service_get
        response = make_soap_connection(conn, :get_consents_for_care_provider, message)
        ns_consents_res = get_from_all_assertions_result(response.body)
        if ns_consents_res[:result][:result_code] == ENV['SOAP_RESPONSE']
          if ns_consents_res[:assertions].present?
            more_consents = fetching_more_nat_consents(response.body, care_id)
            nat_consents[:assertions] << more_consents[0]
            nat_consents[:cancelled] << more_consents[1] unless more_consents[1].nil?
          else
            Logging.logger.info "No assertions records retrieved for the care provider id: #{care_id}"
            next
          end
        else
          raise StandardError,
                "Encountered Error: #{ns_consents_res[:result][:result_code]} from Inera/NS while retrieving data!"
        end
      end
      return nat_consents if nat_consents[:assertions].size.zero?

      nat_consents[:assertions] = nat_consents[:assertions].flatten unless nat_consents[:assertions].nil?
      nat_consents[:cancelled] = nat_consents[:cancelled].flatten unless nat_consents[:cancelled].nil?
      nat_consents
    end

    # Public: Iterate and fetch all the consents records from the response, depending on the has_more_flag.
    #
    # nat_consents_arr - Valid response from the national service.
    # care_id - Care provider id
    #
    # Returns: Consents json response in array format
    def fetching_more_nat_consents(response_arr, care_id)
      nat_consents_arr = []
      has_more_flag = get_from_all_assertions_result(response_arr).dig(:has_more)
      timestamp = get_from_all_assertions_result(response_arr).dig(:more_on_or_after)
      nat_consents_arr[0] = get_from_all_assertions_result(response_arr).dig(:assertions)
      nat_consents_arr[1] = get_from_all_assertions_result(response_arr).dig(:cancelled_assertions)

      while has_more_flag
        message = message_get(care_id, timestamp)
        conn = national_consent_service_get
        response = make_soap_connection(conn, :get_consents_for_care_provider, message)
        nat_consents_arr[0] << get_from_all_assertions_result(response.body[:assertions])
        nat_consents_arr[1] << get_from_all_assertions_result(response.body[:cancelled_assertions]) unless
            get_from_all_assertions_result(response.body)[:cancelled_assertions].nil?
        has_more_flag = get_from_all_assertions_result(response.body).dig(:has_more)
        timestamp = get_from_all_assertions_result(response.body).dig(:more_on_or_after)
      end
      Logging.logger.info "Assertions records retrieved: #{nat_consents_arr[0].size}, for Inera CP id: #{care_id}."
      Logging.logger.info "Timestamp: #{post_timestamp(care_id, timestamp)}, posted to Metastore for this CP."
      nat_consents_arr
    end

    # Public: Check if any of the services (Inera||HEL) response null/empty data then process accordingly.
    #
    # Returns: Void
    def mapping_all_new_consents(nat_recs, hel_recs)
      if nat_recs.size.zero? && hel_recs.size.zero?
        Logging.logger.info 'No records retrieved from either Inera or Consent service! Exiting..'
      elsif hel_recs.size.zero?
        Logging.logger.info 'No records retrieved from Consent service.'
        mapping_new_national_recs(nat_recs)
      elsif nat_recs.size.zero?
        Logging.logger.info 'No records retrieved from Inera service.'
        mapping_hel_recs(hel_recs)
      else
        mapping_hel_recs(hel_recs, nat_recs)
        mapping_new_national_recs(nat_recs, hel_recs)
      end
    end

    # Public: Check & Identify the case where there has already been a post to Inera service and if for some reason that
    #         record isn't updated to CS then this condition checks if there is an already existing national record in
    #         Inera which has a matching consent Id in CS so if the match is found then that record is just updated
    #         instead of the default attempt to re-add to Inera service.
    #
    # hel - Consents records from the HEL/CS service.
    # national - Assertions records from National/Inera service.
    #
    # Returns: Void
    def mapping_hel_recs(*serv_recs)
      Logging.logger.info "Total Consent service records: #{serv_recs[0].size}"
      new_recs_count = 0
      update_recs_count = 0
      last_update_count = 0
      serv_recs[0].each do |hel_rec|
        if hel_rec[:policyRule][:concept] == ENV['PR_CONCEPT']
          unless hel_rec[:aliases].any? { |hel| hel[:system] == ENV['SYSTEM'] && hel[:value].present? }
            consent_id = hel_rec[:consentId]
            match = serv_recs[1].any? { |nat_rec| nat_rec[:assertion_id] == consent_id } if serv_recs[1].present?
            if match
              updated_status = updating_to_hel_ser(hel_rec)
            else
              new_count, update_count = mapping_new_hel_recs(hel_rec)
              new_recs_count += new_count
              update_recs_count += update_count
            end
          end
          last_update_count += 1 if updated_status == 201
        else
          Logging.logger.info "Skipping the record, PR concept #{hel_rec[:policyRule][:concept]} is not accepted!"
        end
      end
      Logging.logger.info "Consent service records (leftover from last run) UPDATED: #{last_update_count}"
      Logging.logger.info "New Consent service records ADDED to Inera service: #{new_recs_count}"
      Logging.logger.info "Consent service records UPDATED in Consent service: #{update_recs_count}"
    end

    # Public: ADD new HEL/CS records to NS/Inera and UPDATE in HEL/CS. When a record has expected Policy Rule concept
    #         but doesn't have a System & its value in aliases then the record is sent to be added to the Inera/NS &
    #         updated to the HEL/CS.
    #
    # hel - Consents record
    #
    # Returns: An array of int count of Added & updated records
    def mapping_new_hel_recs(hel_rec)
      count = [0, 0]
      new_status = adding_to_national_ser(hel_rec)
      if new_status == ENV['SOAP_RESPONSE']
        count[0] += 1
        updated_status = updating_to_hel_ser(hel_rec)
      elsif new_status == true
        Logging.logger.error 'POST to Inera/NS and UPDATE to CS aborted, as the post failed validation check!'
      else
        Logging.logger.error 'POST to Inera/NS and UPDATE to CS aborted, as the post attempt failed.'
      end
      count[1] += 1 if updated_status == 201
      count
    end

    # Public: Add new Inera records to HEL/CS service if Consent's aliases's system & value doesn't match
    #         with the NS assertion id, it is then send for addition.
    #
    # national - Response sent from the National/Inera Service
    # hel - Response sent from the HEL/CS service
    #
    # Returns: Void
    def mapping_new_national_recs(*serv_recs)
      new_records_counter = 0
      Logging.logger.info "Total Inera/NS records: #{serv_recs[0].size}"
      if serv_recs[1].nil? || serv_recs[1].size.zero?
        serv_recs[0].each { |nat_rec| new_records_counter += post_nat_rec_to_hel(nat_rec) }
      else
        serv_recs[0].each do |nat_rec|
          match = nil
          assertion_id = nat_rec[:assertion_id]
          serv_recs[1].each do |hel_rec|
            match = hel_rec[:aliases].any? { |hel| hel[:system] == ENV['SYSTEM'] && hel[:value] == assertion_id }
            break if match
          end
          new_records_counter += post_nat_rec_to_hel(nat_rec) unless match
        end
      end
      Logging.logger.info "New Inera/NS records ADDED to Consent service: #{new_records_counter}"
    end

    private

    # Internal: Addition of Inera record to HEL/Consent service being performed in a loop
    #
    # Returns: Integer 1/0 depending on the state of the Post request. 1 if the Post was successful, 0 otherwise.
    def post_nat_rec_to_hel(record)
      adding_to_hel_ser(record) == 201 ? 1 : 0
    end

    # Internal: Simplify the Inera/NS response structure by eliminating a few nested fields
    #
    # Returns: Hash object of the field get_all_assertions_result
    def get_from_all_assertions_result(nat_consents_arr)
      nat_consents_arr
        .dig(:get_consents_for_care_provider_response)
        .dig(:get_all_assertions_result)
    end

    # Internal: Builds the soap message based on the mode i.e. batch or incremental
    #
    # care_id -    Care provider Id for which the soap call is to be made.
    # timestamp -  Timestamp supplied by the more_on_or_after field or from the metastore for incremental mode.
    #
    # Returns: calls the method soap_message which builts it with the supplied configs
    def message_get(care_id, timestamp)
      if ENV['MODE'] == 'incremental'
        if timestamp.nil?
          timestamp = timestamp_get(care_id)
          return if timestamp.nil?

          soap_message(care_id, Time.parse(timestamp).utc.iso8601, false)
        else
          soap_message(care_id, timestamp, false)
        end
      else
        soap_message(care_id, timestamp, true)
      end
    end

    # Internal: Builds the config schema to be used by the Soap call to Inera service.
    #
    # configs[0] - Care provider Id for which the soap call is to be made.
    # configs[1] - Timestamp(optional): specifies from what time consent certificates have not been collected.
    # configs[2] - Flag that determines if canceled and revoked consent certificates that are not expired.
    #
    # Returns: schema built with the supplied configs to make the soap call with.
    def soap_message(*configs)
      {
        'ns3:careProviderId' => configs[0],
        'ns3:CreatedOnOrAfter' => configs[1],
        'ns3:getCancelledFlag' => configs[2]
      }
    end
  end
end
