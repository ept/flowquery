module FlowQuery
  class SyntaxNode < Treetop::Runtime::SyntaxNode
    attr_accessor :variable, :node_id

    def bind_variables(variable_binding)
      # Subclasses should override this
    end

    def inspect
      "#<#{self.class.name}: #{self}>"
    end
  end

  class Identifier < SyntaxNode
    def to_s
      text_value
    end
  end

  class FunctionDefinition < SyntaxNode
    def params
      param_list.respond_to?(:params) ? param_list.params : []
    end

    def bind_variables(variable_binding)
      self.variable = variable_binding.define(defined_name, self)
      inner_binding = VariableBinding.new(variable_binding)
      params.each{|param| param.bind_variables(inner_binding) }
      value.bind_variables(inner_binding)
    end

    def to_s
      "#{defined_name}(#{params.map(&:to_s).join(', ')}) = #{value}"
    end
  end

  class ParamDeclaration < SyntaxNode
    def bind_variables(variable_binding)
      self.variable = variable_binding.define(name, self)
    end

    def to_s
      "#{type} #{name}"
    end
  end

  class FunctionApplication < SyntaxNode
    def arguments
      argument_list.arguments
    end

    def bind_variables(variable_binding)
      self.variable = variable_binding.reference(name, self)
      arguments.each{|argument| argument.bind_variables(variable_binding) }
    end

    def to_s
      "#{name}(#{arguments.map(&:to_s).join(', ')})"
    end
  end

  class VariableReference < SyntaxNode
    def bind_variables(variable_binding)
      self.variable = variable_binding.reference(name, self)
    end

    def to_s
      name.to_s
    end
  end

  class QueryFile < SyntaxNode
    def self.parse(query_file)
      parser = FlowQueryParser.new
      tree = parser.parse(query_file) or raise SyntaxError, parser.failure_reason
      raise SyntaxError, 'file is not a complete query' unless tree.is_a? QueryFile
      globals = VariableBinding.new
      tree.bind_variables(globals)
      if !(undefined = globals.undefined).empty?
        raise SyntaxError, "undefined variable: #{undefined.map(&:name).join(', ')}"
      end
      globals
    end

    def bind_variables(variable_binding)
      functions.each{|function| function.bind_variables(variable_binding) }
    end

    def to_s
      functions.map(&:to_s).join('; ')
    end
  end


  class VariableBinding
    attr_reader :parent

    def initialize(parent=nil)
      @parent = parent
      @variables = {}
    end

    def [](name)
      name = name.to_s
      @variables[name] || (parent && parent[name]) || (@variables[name] = Variable.new(name))
    end

    def define(name, node)
      name = name.to_s
      @variables[name] ||= Variable.new(name)
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

    class Variable
      attr_reader :name, :definition, :references

      def initialize(name)
        @name = name
        @definition = nil
        @references = []
      end

      def definition=(new_definition)
        raise SyntaxError, "duplicate variable #{name}" if definition
        @definition = new_definition
      end
    end
  end
end
