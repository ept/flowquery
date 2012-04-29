module FlowQuery
  class VariableBinding
    attr_reader :parent

    def initialize(parent=nil)
      @parent = parent
      @variables = {}
    end

    def [](name)
      name = name.to_s

      if @variables.include? name
        # Variable already defined in local scope
        @variables[name]

      elsif parent
        # This is an inner scope; search outer scope
        parent[name]

      else
        # This is already the global scope; create a reference without definition, and hopefully
        # we'll get to fill in the definition later.
        @variables[name] = Variable.new(name, self)
      end
    end

    def define(name, node)
      name = name.to_s
      @variables[name] ||= Variable.new(name, self)
      @variables[name].tap{|var| var.definition = node }
    end

    def reference(name, node)
      self[name].tap{|var| var.references << node }
    end

    def variables
      @variables.values
    end

    def undefined
      variables.select{|variable| variable.definition.nil? }
    end

    def global?
      parent.nil?
    end

    class Variable
      attr_reader :name, :definition, :references, :scope

      def initialize(name, scope)
        @name = name
        @definition = nil
        @references = []
        @scope = scope
      end

      def definition=(new_definition)
        raise SyntaxError, "duplicate variable #{name}" if definition
        @definition = new_definition
      end
    end
  end
end
