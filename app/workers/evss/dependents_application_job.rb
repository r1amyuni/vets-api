# frozen_string_literal: true

module EVSS
  class DependentsApplicationJob
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform(id, form, user_uuid)
      Sentry::TagRainbows.tag
      dependents_application = DependentsApplication.find(id)
      user = User.find(user_uuid)
      service = Dependents::Service.new(user)

      # TODO: used cached method
      evss_form = service.retrieve
      merged_form = DependentsApplication.transform_form(form, evss_form)
      merged_form = service.clean_form(merged_form)
      res = service.validate(merged_form)

      if res['errors'].present?
        return dependents_application.update_attributes!(
          state: 'failed',
          response: res.to_json
        )
      end

    end
  end
end
