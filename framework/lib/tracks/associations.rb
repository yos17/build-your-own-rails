module Tracks
  module Associations
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def belongs_to(name, class_name: nil, foreign_key: nil)
        fk    = foreign_key || "#{name}_id"
        klass = class_name  || name.to_s.capitalize

        define_method(name) do
          Object.const_get(klass).find(@attributes[fk])
        end

        define_method("#{name}=") do |obj|
          @attributes[fk] = obj&.id
        end
      end

      def has_many(name, class_name: nil, foreign_key: nil)
        klass = class_name  || name.to_s.chomp("s").capitalize
        fk    = foreign_key || "#{self.name.downcase}_id"

        define_method(name) do
          Object.const_get(klass).where(fk => @attributes["id"])
        end
      end

      def has_one(name, class_name: nil, foreign_key: nil)
        klass = class_name  || name.to_s.capitalize
        fk    = foreign_key || "#{self.name.downcase}_id"

        define_method(name) do
          Object.const_get(klass).find_by(fk => @attributes["id"])
        end
      end
    end
  end
end
