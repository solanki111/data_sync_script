# frozen_string_literal: true

require_relative '../clients/rest.rb'

module Helper
  # Public: Update feature for the services.
  module UpdateConsents
    include Clients::Rest

    # Public: Updating the new record in HI with the alias id.
    #
    # record - A block of HI record sent from a loop.
    #
    # Returns: Status of the sent request.
    def updating_to_hel_ser(record)
      consent_id = record[:consentId]
      patient_id = record[:patientId]
      aliases = [
        {
          system: ENV['SYSTEM'],
          value: consent_id
        }
      ]
      body = {
        aliases: aliases
      }
      updated_consents = {
        body: body,
        relativeUrl: "#{ENV['POP_ID']}/patients/#{patient_id}/patient-consents/#{consent_id}"
      }
      # Send updated mapped consent records to hi service
      update_hel_consents(updated_consents)
    end
  end
end
