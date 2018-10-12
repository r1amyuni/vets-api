# frozen_string_literal: true

class DependentsApplication < Common::RedisStore
  include RedisForm

  validates(:user, presence: true, unless: :persisted?)
  validate(:user_can_access_evss, unless: :persisted?)

  FORM_ID = '21-686C'
  MARRIAGE_TYPES = {
    'Married' => 'MARRIED',
    'Never Married' => 'NEVERMARRIED',
    'Separated' => 'SEPARATED',
    'Widowed' => 'WIDOWED',
    'Divorced' => 'DIVORCED'
  }
  SEPARATION_TYPES = {
    'Death' => 'DEATH',
    'Divorce' => 'DIVORCED',
    'Other' => 'OTHER'
  }

  def self.filter_children(dependents, evss_children)
    return [] if evss_children.blank? || dependents.blank?

    evss_children.find_all do |child|
      ssn = child['ssn'].gsub('-', '')

      dependents.find do |dependent|
        dependent['childSocialSecurityNumber'] == ssn
      end
    end
  end

  def self.convert_marriage_status(marital_status)
    MARRIAGE_TYPES[marital_status]
  end

  def self.convert_evss_date(date)
    Date.parse(date).to_time(:utc).iso8601
  end

  def self.convert_name(full_name)
    converted = {}
    return converted if full_name.blank?

    %w[first middle last].each do |type|
      converted["#{type}Name"] = full_name[type] if full_name[type].present?
    end

    converted
  end

  def self.convert_ssn(ssn)
    return {} if ssn.blank?

    {
      'ssn' => StringHelpers.hyphenated_ssn(ssn)
    }
  end

  def self.convert_address(address)
    converted = {}
    return converted if address.blank?

    converted['address'] = {
      'addressLine1' => address['street'],
      'addressLine2' => address['street2'],
      'addressLocality' => address['addressType'],
      'city' => address['city'],
      'country' => {
        'dropDownCountry' => address['country']
      },
      'postOffice' => address['postOffice'],
      'postalType' => address['postalType'],
      'state' => address['state'],
      'zipCode' => address['postalCode']
    }

    converted
  end

  def self.convert_country(location)
    return {} if location.blank?

    {
      'dropDownCountry' => location['countryDropdown'],
      'textCountry' => location['countryText']
    }
  end

  def self.convert_previous_marriages(previous_marriages)
    return [] if previous_marriages.blank?

    previous_marriages.map do |previous_marriage|
      {
        'marriedDate' => previous_marriage['dateOfMarriage'],
        'city' => previous_marriage['locationOfMarriage']['city'],
        'country' => convert_country(previous_marriage['locationOfMarriage']),
        'terminatedDate' => convert_evss_date(previous_marriage['dateOfSeparation']),
        'marriageTerminationReasonType' => SEPARATION_TYPES[previous_marriage['reasonForSeparation']],
        'explainTermination' => previous_marriage['explainSeparation'],
        'state' => previous_marriage['locationOfMarriage']['state']
      }.merge(
        convert_name(previous_marriage['spouseFullName'])
      )

    end
  end

  def self.convert_marriage(parsed_form)
    converted = {}
    current_marriage = parsed_form['currentMarriage']
    # TOOD handle current marriage nil
    converted.merge!(convert_address(parsed_form['spouseAddress']))
    converted.merge!(convert_name(parsed_form['spouseFullName']))
    converted.merge!(convert_ssn(parsed_form['spouseSocialSecurityNumber']))

    converted['dateOfBirth'] = convert_evss_date(parsed_form['spouseDateOfBirth'])

    converted['currentMarriage'] = {
      'marriageDate' => convert_evss_date(current_marriage['dateOfMarriage']),
      'city' => current_marriage['locationOfMarriage']['city'],
      'country' => convert_country(current_marriage['locationOfMarriage']),
      'state' => current_marriage['locationOfMarriage']['state']
    }

    converted['vaFileNumber'] = convert_ssn(parsed_form['spouseVaFileNumber'])
    converted['veteran'] = parsed_form['spouseIsVeteran']
    converted['previousMarriages'] = convert_previous_marriages(parsed_form['spouseMarriages'])

    converted
  end

  def self.convert_phone(phone)
    return {} if phone.blank?

    {
      'areaNbr' => phone[0..2],
      'phoneNbr' => "#{phone[3..5]}-#{phone[6..9]}"
    }
  end

  def self.set_child_attrs!(dependent, child = {})
    child.merge!(convert_name(dependent['fullName']))

    child.merge!(convert_address(dependent['childAddress']))

    dependent['childPlaceOfBirth'].tap do |place_of_birth|
      next if place_of_birth.blank?

      child['countryOfBirth'] = convert_country(place_of_birth)
      child['cityOfBirth'] = place_of_birth['city']
      child['stateOfBirth'] = place_of_birth['state']
    end

    child.merge!(convert_ssn(dependent['childSocialSecurityNumber']))

    [
      ['attendedSchool', 'attendingCollege'],
      ['disabled', 'disabled'],
      ['married', 'previouslyMarried']
    ].each do |attrs|
      val = dependent[attrs[1]]
      next if val.nil?
      child[attrs[0]] = val
    end

    [
      ['dateOfBirth', 'childDateOfBirth'],
      ['marriedDate', 'marriedDate']
    ].each do |attrs|
      val = dependent[attrs[1]]
      next if val.blank?
      child[attrs[0]] = convert_evss_date(val)
    end

    child
  end

  def self.transform_form(parsed_form, evss_form)
    dependents = parsed_form['dependents'] || []
    transformed = {}
    transformed['emailAddress'] = parsed_form['veteranEmail']
    transformed.merge!(convert_name(parsed_form['veteranFullName']))
    transformed.merge!(convert_address(parsed_form['veteranAddress']))
    transformed.merge!(convert_ssn(parsed_form['veteranSocialSecurityNumber']))
    transformed['vaFileNumber'] = convert_ssn(parsed_form['vaFileNumber'])

    transformed['spouse'] = convert_marriage(parsed_form)
    transformed['spouse']['address'] = transformed['address'] if parsed_form['liveWithSpouse']
    # TODO add no ssn fields

    children = filter_children(
      dependents,
      evss_form['submitProcess']['veteran']['children']
    )

    parsed_form['dependents'].each do |dependent|
      child = children.find do |c|
        c['ssn'] == dependent['childSocialSecurityNumber']
      end

      if child
        set_child_attrs!(dependent, child)
      else
        children << set_child_attrs!(dependent)
      end
    end
    transformed['children'] = children

    transformed['marriageType'] = convert_marriage_status(parsed_form['maritalStatus']) if parsed_form['maritalStatus'].present?

    transformed['previousMarriages'] = convert_previous_marriages(parsed_form['previousMarriages'])

    evss_form['submitProcess']['veteran'].merge!(transformed)

    Common::HashHelpers.deep_compact(evss_form)
  end

  private

  def user_can_access_evss
    errors[:user] << 'must have evss access' unless user.authorize(:evss, :access?)
  end

  def create_submission_job
    # TODO
  end
end