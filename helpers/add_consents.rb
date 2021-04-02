# frozen_string_literal: true

require_relative '../clients/rest.rb'
require_relative '../clients/soap.rb'
require_relative '../helper/logging.rb'

module Helper
  # Public: Add feature for the services.
  module AddConsents
    include Logging
    include Clients::Rest
    include Clients::Soap

    # Initialize logger
    Logging.setup(Logger::INFO)

    # Public: Mapping and sending the identified record for addition to Consent/HI service.
    #
    # record - A block of National record sent from a loop.
    #
    # Returns: Status of the sent request.
    def adding_to_hel_ser(record)
      patient_id = get_patient_id_by_alias(record[:patient_id][:root], record[:patient_id][:extension])
      return Logging.logger.error 'Aborting Post to Consent Service, no Patient Id was retrieved for the above record!'\
       if patient_id.nil?

      aliases = [
        {
          system: ENV['SYSTEM'],
          value: record[:assertion_id]
        }
      ]
      effective_period = {
        start: record[:start_date].to_s,
        end: record[:end_date].to_s
      }
      consent_type = record[:assertion_type]
      organization_group = { id: record[:care_provider_id] }
      organization = { id: record[:care_unit_id] }
      personnel = { id: record[:employee_id] }

      provision_scope = {
        organizationGroup: organization_group,
        organization: organization,
        personnel: personnel
      }
      consent_type =
        if consent_type == 'Consent'
          'PATIENT_GRANTED'
        elsif consent_type == 'Emergency'
          'EMERGENCY_ACCESS'
        else
          'NOT_FOUND'
        end
      body = {
        aliases: aliases,
        patientId: patient_id,
        createdBy: record[:employee_id],
        consentReasonType: consent_type,
        effectivePeriod: effective_period,
        provisionScope: provision_scope,
        emergencyConsentReason: consent_type,
        provisionType: ENV['PROVISION_TYPE'],
        category: ENV['CATEGORY_CONCEPT'],
        policyRule: ENV['PR_CONCEPT']
      }
      # Post-url: /patients/{patient_id}/patient-consents:
      new_hel_consents = {
        body: body,
        relativeUrl: "#{ENV['POP_ID']}/patients/#{patient_id}/patient-consents",
        assertion_id: record[:assertion_id]
      }
      # Send new mapped consent records to HEL service
      post_hel_consents(new_hel_consents)
    end

    # Public: Mapping and sending the identified HEL record for addition to National service.
    #
    # record - A block of HEL record sent from a loop.
    #
    # Returns: Status of the sent request.
    def adding_to_national_ser(record)
      if record[:provisionScope].size < 2
        return Logging.logger.error 'Aborting Post to Inera/NS, provisionScope doesn\'t have the required fields'
      end

      care_provider_id = record[:provisionScope][:organizationGroup][:id]
      care_unit_id = record[:provisionScope][:organization][:id]
      employee_id =
        if record[:provisionScope][:personnel][:id].blank?
          record[:createdBy] ? nil : record[:createdBy]
        else
          record[:provisionScope][:personnel][:id]
        end

      if employee_id.nil? || record[:effectivePeriod][:start].blank?
        return Logging.logger.error 'Aborting Post to Inera/NS, effective-period or employee-id can\'t be empty.'
      end

      actor_type = {
        'ns2:employeeId' => employee_id
      }
      assertion_id = record[:consentId]
      patient_id = record[:patientId]
      assertion_type = record[:consentReasonType]
      aliases = get_alias_by_patient_id(patient_id)
      return Logging.logger.error 'Aborting Post to Inera/NS, no aliases found!' if aliases[:value].blank?

      patient_id = {
        'ns2:root' => aliases[:system],
        'ns2:extension' => aliases[:value]
      }

      assertion_type =
        if assertion_type == 'PATIENT_GRANTED'
          'Consent'
        elsif assertion_type == 'EMERGENCY_ACCESS'
          'Emergency'
        else
          'NOT_FOUND'
        end

      registration_action = {
        'ns2:requestDate' => record[:effectivePeriod][:start],
        'ns2:requestedBy' => actor_type,
        'ns2:registrationDate' => record[:effectivePeriod][:start],
        'ns2:registeredBy' => actor_type,
        'ns2:reasonText' => record[:emergencyConsentReason]
      }
      body = {
        'ns3:assertionId' => assertion_id,
        'ns3:assertionType' => assertion_type,
        'ns3:scope' => ENV['SCOPE'],
        'ns3:patientId' => patient_id,
        'ns3:careProviderId' => care_provider_id,
        'ns3:careUnitId' => care_unit_id,
        'ns3:employeeId' => employee_id,
        'ns3:startDate' => record[:effectivePeriod][:start],
        'ns3:endDate' => record[:effectivePeriod][:end],
        'ns3:registrationAction' => registration_action
      }

      # Send new mapped consent records to national service
      begin
        conn = post_national_consent_service
        response = make_soap_connection(conn, :register_extended_consent, body)
        post_result = response.body[:register_extended_consent_response][:result]

        unless post_result[:result_code] == ENV['SOAP_RESPONSE']
          Logging.logger.error "POST to Inera/NS failed with error code: '#{post_result[:result_code]}'" \
          " and text '#{post_result[:result_text]}'"
        end
        post_result[:result_code]
      rescue NoMethodError => e
        Logging.logger.error "Invalid response from National Service(POST)! #{e.inspect}"
        raise e, 'Invalid response from National Service(POST)!'
      end
    end
  end
end
