# frozen_string_literal: true

require 'backend_services'
require 'common/client/concerns/service_status'

class UserSerializer < ActiveModel::Serializer
  include Common::Client::ServiceStatus

  attributes :services, :profile, :va_profile, :veteran_status, :mhv_account_state, :health_terms_current,
             :in_progress_forms, :prefills_available

  def id
    nil
  end

  def profile
    {
      email: object.email,
      first_name: object.first_name,
      middle_name: object.middle_name,
      last_name: object.last_name,
      birth_date: object.birth_date,
      gender: object.gender,
      zip: object.zip,
      last_signed_in: object.last_signed_in,
      loa: object.loa,
      multifactor: object.multifactor,
      authn_context: object.authn_context
    }
  end

  def va_profile
    status = object.va_profile_status
    return { status: status } unless status == RESPONSE_STATUS[:ok]
    {
      status: status,
      birth_date: object.va_profile.birth_date,
      family_name: object.va_profile.family_name,
      gender: object.va_profile.gender,
      given_names: object.va_profile.given_names
    }
  end

  def veteran_status
    {
      status: RESPONSE_STATUS[:ok],
      is_veteran: object.veteran?
    }
  rescue EMISRedis::VeteranStatus::NotAuthorized
    { status: RESPONSE_STATUS[:not_authorized] }
  rescue EMISRedis::VeteranStatus::RecordNotFound
    { status: RESPONSE_STATUS[:not_found] }
  rescue StandardError
    { status: RESPONSE_STATUS[:server_error] }
  end

  def health_terms_current
    !object.mhv_account.needs_terms_acceptance?
  end

  def in_progress_forms
    object.in_progress_forms.map do |form|
      {
        form: form.form_id,
        metadata: form.metadata,
        last_updated: form.updated_at.to_i
      }
    end
  end

  def prefills_available
    return [] unless object.identity.present? && object.can_access_prefill_data?
    FormProfile.prefill_enabled_forms
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def services
    service_list = [
      BackendServices::FACILITIES,
      BackendServices::HCA,
      BackendServices::EDUCATION_BENEFITS
    ]
    service_list += BackendServices::MHV_BASED_SERVICES if object.mhv_account_eligible?
    service_list << BackendServices::EVSS_CLAIMS if object.authorize :evss, :access?
    service_list << BackendServices::USER_PROFILE if object.can_access_user_profile?
    service_list << BackendServices::APPEALS_STATUS if object.can_access_appeals?
    service_list << BackendServices::SAVE_IN_PROGRESS if object.can_save_partial_forms?
    service_list << BackendServices::FORM_PREFILL if object.can_access_prefill_data?
    service_list << BackendServices::ID_CARD if object.authorize :id_card, :access?
    service_list << BackendServices::IDENTITY_PROOFED if object.identity_proofed?
    service_list
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
