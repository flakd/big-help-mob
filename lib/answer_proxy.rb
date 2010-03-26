class AnswerProxy
  extend ActiveModel::Naming
  include ActiveModel::Validations
  
  VALID_NAME_REGEXP = /^question_\d+\=?$/
  
  validate :check_answer_status
  
  def self.i18n_scope
    :answer_model
  end
  
  attr_reader :participation, :mission, :questions
  
  def initialize(participation)
    @participation = participation
    @mission       = participation.mission
    @questions     = @mission.questions
  end
  
  def attributes=(attributes)
    attributes.each_pair do |k, v|
      write_attribute(k, v) if k.to_s =~ VALID_NAME_REGEXP
    end
  end
  
  def each_question(&blk)
    @questions.each do |question|
      yield question, question_to_param(question)
    end
  end
  
  def answers
    @answers ||= begin
      value = @participation[:answers]
      if !value.is_a?(Hash)
        value = {}
        @participation[:answers] = value
      end
      value
    end
  end
  
  def needed?
    !@questions.empty?
  end
  
  def write_attribute(name, value)
    answers[name.to_s] = normalize_value(question_for_name(name), value)
  end
  
  def read_attribute(name)
    answers[name.to_s]
  end
  
  def question_for_name(name)
    @questions.detect { |q| q.id == param_to_id(name) }
  end
  
  def method_missing(name, *args, &blk)
    if (question = question_for_name(name)).present?
      assign = name.to_s[-2, 1] == "="
      assign ? write_attribute(name, *args) : read_attribute(name)
    else
      super
    end
  end
  
  def respond_to?(name, include_private = false)
    !!(name.to_s =~ VALID_NAME_REGEXP) || super
  end
  
  def check_answer_status
    each_question do |question, key|
      value = read_attribute(key)
      if value.blank? && question.required?
        errors.add(key, :blank, :default => "is blank")
      elsif value.present? && question.multiple_choice?
        valid_choice = Array(question.metadata).include?(value)
        errors.add(key, :invalid_choice, :default => "is an invalid choice") unless valid_choice
      end
    end
  end
  
  protected
  
  def question_to_param(question, suffix = "")
    :"question_#{question.id}#{suffix}"
  end
  
  def param_to_id(id)
    id.to_s.scan(/\d+/).first.to_i
  end
  
  def normalize_value(question, value)
    return ActiveRecord::ConnectionAdapters::Column.value_to_boolean(value) if question.boolean?
    value.to_s
  end
  
end