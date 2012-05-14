module Flowquery
  class Type
    attr_accessor :current_type

    def initialize(current_type)
      @current_type = current_type
    end

    def unify_with!(other_type)
      current_type.unify_with! other_type.current_type
    end


    class Base
      attr_accessor :references

      def self.make(*args)
        new_type = self.new(*args)
        Type.new(new_type).tap do |wrapper|
          new_type.references = [wrapper]
        end
      end

      def replace_with!(other_type)
        return if self == other_type
        references.each do |wrapper|
          wrapper.current_type = other_type
          other_type.references << wrapper
        end
        self.references = []
      end

      def unify_with!(other_type, swapped=false)
        # default is uncooperative. subclasses should override.
        return if self == other_type
        raise ParseError, "cannot unify #{self.inspect} with #{other_type.inspect}" if swapped
        other_type.unify_with!(self, true)
      end
    end


    class Singleton < Base
      def self.make
        @instance ||= self.new
        @instance.references ||= []
        Type.new(@instance).tap do |wrapper|
          @instance.references << wrapper
        end
      end
    end


    class Variable < Base
      def unify_with!(other_type, swapped=false)
        replace_with!(other_type)
      end
    end

    class Boolean < Singleton; end

    class Function < Base
      attr_reader :param_types, :return_type

      def initialize(param_types, return_type)
        @param_types, @return_type = param_types, return_type
      end

      def unify_with!(other_type, swapped=false)
        if other_type.is_a? Function
          if param_types.size != other_type.param_types.size
            raise ParseError, "arity mismatch: #{param_types.size} != #{other_type.param_types.size}"
          end
          param_types.zip(other_type.param_types).each do |own, other|
            own.unify_with! other
          end
          return_type.unify_with! other_type.return_type
        else
          super
        end
      end
    end

    class Table < Base
      attr_reader :columns

      def initialize(columns)
        @columns = columns
      end
    end

    class Column < Base
      attr_reader :type_name

      def initialize(type_name)
        @type_name = type_name
      end

      def unify_with!(other_type, swapped=false)
        if other_type.is_a? Column
          if type_name != other_type.type_name
            raise ParseError, "type mismatch: #{type_name} != #{other_type.type_name}"
          end
        else
          super
        end
      end
    end
  end
end
