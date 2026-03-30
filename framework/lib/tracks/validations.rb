module Tracks
  module Validations
    def self.included(base)
      base.instance_variable_set(:@validations, [])
      base.extend(ClassMethods)
    end

    module ClassMethods
      def validates(field, **rules)
        @validations ||= []
        @validations << { field: field.to_s, rules: rules }
      end

      def validations
        @validations || []
      end
    end

    def valid?
      @errors = {}
      self.class.validations.each do |v|
        field = v[:field]
        value = @attributes[field]
        rules = v[:rules]

        if rules[:presence] && (value.nil? || value.to_s.strip.empty?)
          add_error(field, "can't be blank")
        end

        if (len = rules[:length])
          str = value.to_s
          add_error(field, "is too short (min #{len[:min]})") if len[:min] && str.length < len[:min]
          add_error(field, "is too long (max #{len[:max]})")  if len[:max] && str.length > len[:max]
        end

        if rules[:uniqueness] && !value.nil?
          existing = self.class.find_by(field => value)
          add_error(field, "must be unique") if existing && existing.id != @attributes["id"]
        end
      end

      @errors.empty?
    end

    def errors
      @errors ||= {}
    end

    private

    def add_error(field, msg)
      @errors[field] ||= []
      @errors[field] << msg
    end
  end
end
