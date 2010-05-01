class Email
  include ActiveModel::Conversion
  include ActiveModel::AttributeMethods
  include ActiveModel::Validations
  include ActiveModel::Serializers::JSON
  extend  ActiveModel::Naming
  
  SCOPE_TYPES = [["All Users", "users"], ["Filtered Participations", "participations"]]
  
  ASSIGNABLE_ATTRIBUTES = [:subject, :html_content, :text_content, :scope_type, :filter, :confirmed]
  attr_accessor           *ASSIGNABLE_ATTRIBUTES
  define_attribute_methods ASSIGNABLE_ATTRIBUTES
  
  validates_presence_of  :subject
  validates_inclusion_of :scope_type, :in => SCOPE_TYPES.map(&:last)
  validate               :has_atleast_one_content_type
  validate               :has_atleast_one_user
  validate               :ensure_confirmed_is_checked
  
  def initialize(attributes = {})
    self.attributes = attributes
  end
  
  def attributes=(attributes)
    return unless attributes.is_a?(Hash)
    attributes.symbolize_keys.each_pair do |k, v|
      send :"#{k}=", v if ASSIGNABLE_ATTRIBUTES.include? k.to_sym
    end
  end
  
  def attributes
    @attributes ||= ASSIGNABLE_ATTRIBUTES.inject({}) { |m, c| m[c.to_s] = 'nil'; m }
  end
  
  def filter
    @filter ||= OpenStruct.new
  end
  
  def filter=(value)
    if value.blank? || !value.is_a?(Hash)
      @filter = OpenStruct.new
    else
      value = value["table"] if value.keys == ["table"]
      @filter = OpenStruct.new(value.stringify_keys)
      @filter.mission_id = @filter.mission_id.to_i if @filter.mission_id.present?
    end
  end
  
  def save
    valid? && send_email
  end
  
  def persisted?
    false
  end
  
  def confirmed=(value)
    if value.blank?
      @confirmed = nil
    else
      @confirmed = ActiveRecord::ConnectionAdapters::Column.value_to_boolean(value.to_s)
    end
  end
  
  def confirmed?
    !!@confirmed
  end
  
  def send_email
    Rails.logger.debug self.to_json
    if [html_content, text_content, subject].any? { |c| c.include?("{{") }
      IndividualUserMailer.queue_for!(self)
    else
      BulkUserMailer.queue_for!(self)
    end
    true
  end
  
  def self.mapping_to_scope(name, filter)
    name  = name.to_s
    scope = User.unscoped
    scope = scope.where('id IN (?)', build_id_list(filter)) if name == "participations"
    scope
  end
  
  def self.build_id_list(filter)
    scope = MissionParticipation.unscoped
    scope = scope.where('mission_id = ?', filter.mission_id.to_i) if filter.mission_id.present?
    scope = scope.only_role(filter.role)       if filter.role.present?
    scope = scope.with_states(filter.states)   if filter.states.present?
    scope = scope.from_pickups(filter.pickups) if filter.pickups.present?
    scope.select(:user_id).all.map(&:user_id).uniq
  end
  
  def valid_other_than_confirmed?
    errors.reject { |k, v| v.blank? }.map { |k, v| k } == [:confirmed]
  end
  
  def user_count
    user_scope.count
  end
  
  def emails
    user_scope.select(:email).map(&:email).uniq
  end
  
  def self.from_json(json)
    allocate.from_json(json)
  end
  
  def each_user_with_scope
    return unless block_given?
    user_scope.find_each do |user|
      yield user, scope_for_user(user)
    end
  end
  
  protected

  def scope_for_user(user)
    scope = {'user' => user}
    if scope_type == 'participations'
      if filter.mission_id.present?
        scope['participation'] = user.mission_participations.find_by_mission_id(filter.mission_id)
      end
    end
    scope
  end

  def user_scope
    self.class.mapping_to_scope(scope_type, filter)
  end
  
  def has_atleast_one_content_type
    if html_content.blank? && text_content.blank?
      errors.add :html_content, "at least one content section must be filled in"
      errors.add :text_content, "at least one content section must be filled in"
    end
  end
  
  def has_atleast_one_user
    errors.add_to_base "There must be atleast one user" if user_scope.size < 1
  end
  
  def ensure_confirmed_is_checked
    errors.add :confirmed, "please confirm the email choice to continue" unless confirmed?
  end
  
end