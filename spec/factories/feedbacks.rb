# frozen_string_literal: true
FactoryGirl.define do
  factory :feedback, class: 'Feedback' do
    target_page '/example/page'
    description 'I liked this page very much.  I used it to help me attain benefits and it was simple and intuitive'

    trait :email_provided do
      owner_email 'joe.vet@aol.com'
    end
  end
end
