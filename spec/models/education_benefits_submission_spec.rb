# frozen_string_literal: true
require 'rails_helper'

RSpec.describe EducationBenefitsSubmission, type: :model do
  let(:attributes) do
    {
      region: 'eastern'
    }
  end
  subject { described_class.new(attributes) }

  describe 'validations' do
    it 'should validate region is correct' do
      subject.region = 'western'
      expect_attr_valid(subject, :region)

      subject.region = 'canada'
      expect_attr_invalid(subject, :region, 'is not included in the list')
    end

    it 'should validate form_type' do
      %w(1995 1990 1990e).each do |form_type|
        subject.form_type = form_type
        expect_attr_valid(subject, form_type)
      end

      subject.form_type = 'foo'
      expect_attr_invalid(subject, :form_type, 'is not included in the list')
    end
  end
end
