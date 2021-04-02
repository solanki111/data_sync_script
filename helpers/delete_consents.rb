# frozen_string_literal: true

require_relative '../clients/rest.rb'

module Helper
  # Public: Delete feature for the services.
  module DeleteConsents
    include Clients::Rest

    # Public: Mapping and sending the identified record for deletion to Consent/HI service.
    #         Only operates in batch mode.
    #
    # record - A block of HI record sent from a loop.
    #
    # Returns: Status of the sent request.
    def deleting_hel_consents(record)
      consent_id = record[:consentId]
      patient_id = record[:patientId]
      deleted_consents = {
        relativeUrl: "#{ENV['POP_ID']}/patients/#{patient_id}/patient-consents/#{consent_id}"
      }
      # Send deleted consents records to consent service
      delete_hel_consents(deleted_consents)
    end
  end
end
