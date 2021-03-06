class MissionParticipation < ActiveRecord::Base
  extend DynamicBaseDrop::Droppable

  belongs_to :user
  belongs_to :mission
  belongs_to :role
  belongs_to :pickup, :class_name => "MissionPickup"

  validates_presence_of :user, :mission
  validates_associated  :user
  validates_presence_of :pickup,  :if     => :validate_pickup_presence?
  validates_associated  :answers, :unless => :skip_extra_validation?

  before_validation :mark_user_participation

  attr_accessible :mission_id, :user_attributes, :pickup_id, :answers, :partaking_with_friends

  after_validation :auto_approve, :on => :update

  validate :check_age_validation

  accepts_nested_attributes_for :user

  serialize :raw_answers

  attr_accessor :skip_extra_validation
  def skip_extra_validation?
    !!skip_extra_validation
  end

  def validate_pickup_presence?
    sidekick? && !skip_extra_validation?
  end

  def recently_joined?
    defined?(@recently_joined) && @recently_joined
  end

  scope :with_role, where('role_id IS NOT NULL')
  scope :for_user,  lambda { |u| where(:user_id => u.id) }

  scope :optimize_editable, includes(:user => [:mailing_address, :captain_application], :pickup => {:pickup => :address}, :role => nil)

  is_droppable

  state_machine :initial => :created do
    state :created
    state :awaiting_approval
    state :approved
    state :completed
    state :cancelled

    event :await_approval do
      transition :created => :awaiting_approval
    end

    event :approve do
      transition [:created, :awaiting_approval] => :approved
    end

    event :cancel do
      transition any => :cancelled
    end

    event :complete do
      transition :approved => :completed
    end

    after_transition :created => :awaiting_approval do |mp, transition|
      mp.user.notify! :joined_mission, mp
    end

    after_transition [:created, :awaiting_approval] => :approved do |mp, transition|
      mp.user.notify! :mission_role_approved, mp
    end

  end

  def captain?
    role_name.captain?
  end

  def sidekick?
    role_name.sidekick?
  end

  def role_name
    ActiveSupport::StringInquirer.new(self.role.try(:name).to_s)
  end

  def role_name=(value)
    self.role = Role::PUBLIC_ROLES.include?(value) ? Role[value] : nil
  end

  def update_with_conditional_save(attributes, perform_save = true)
    self.attributes = attributes
    perform_save && save
  end

  def alternate_role
    Role::PUBLIC_ROLES[((Role::PUBLIC_ROLES.index(role_name) || 0) + 1) % Role::PUBLIC_ROLES.length]
  end

  def answers
    @answers ||= Answers.new(self)
  end

  def answers=(value)
    answers.attributes = value
  end

  # Don't approve before the first save.
  def auto_approve
    if !new_record? && (created? || awaiting_approval?) && errors.empty?
      approve false
      @recently_joined = true
    end
  end

  def state_events_for_select
    state_events.map do |se|
      name = ::I18n.t(:"#{self.class.model_name.underscore}.#{se}", :default => se.to_s.humanize, :scope => :"ui.state_events")
      [name, se]
    end
  end

  def self.viewable_by(user)
    scope = self.includes(:mission => :address, :role => nil, :pickup => {:pickup => :address})
    public_states = %w(approved completed)
    if user.blank?
      scope = scope.where('mission_participations.state' => public_states)
    elsif !user.admin?
      scope = scope.where("mission_participations.user_id = ? OR mission_participations.state IN (?)", user.id, public_states)
    end
    scope
  end

  def self.only_role(name)
    return unscoped if name.blank? || (role = Role[name]).blank?
    with_role.where(:role_id => role.id)
  end

  def self.with_states(states)
    states = Array(states).reject(&:blank?)
    states.blank? ? unscoped : where(:state => states)
  end

  def self.from_pickups(pickup_ids)
    ids = Array(pickup_ids).reject(&:blank?)
    ids.blank? ? unscoped : where('pickup_id IN (?)', ids)
  end

  def mark_user_participation
    if user.present?
      user.build_captain_application if captain? && user.captain_application.blank?
      user.current_participation = self
    end
  end

  def check_age_validation
    role = role_name.to_s.strip
    return if role.blank? || mission.blank? || user.blank? || !%w(captain sidekick).include?(role)
    min_age, max_age = mission.send(:"minimum_#{role}_age"), mission.send(:"maximum_#{role}_age")
    age = user.age || 0
    prefix = role.to_s.humanize.pluralize
    if min_age.present? && max_age.present?
      errors.add_to_base("#{prefix} must be #{min_age}-#{max_age} years old.") unless (min_age..max_age).include?(age)
    elsif min_age.present?
      errors.add_to_base("#{prefix} must be older than #{min_age}.") if age < min_age
    elsif max_age.present?
      errors.add_to_base("#{prefix} must be younger than #{min_age}.") if age > max_age
    end
  end

  def still_preparing?(include_approved = false)
    states = %w(created awaiting_approval)
    states << "approved" if include_approved
    states.include?(self.state)
  end

  def human_state_name
    state.to_s.humanize
  end

  def humanized_pickup
    if role_name.sidekick?
      pickup.present? ? pickup.name : "Not yet set"
    else
      "Not applicable"
    end
  end

end

# == Schema Info
#
# Table name: mission_participations
#
#  id          :integer(4)      not null, primary key
#  mission_id  :integer(4)
#  pickup_id   :integer(4)
#  role_id     :integer(4)
#  user_id     :integer(4)
#  comment     :text
#  raw_answers :text
#  state       :string(255)
#  created_at  :datetime
#  updated_at  :datetime