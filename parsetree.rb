module FlowQuery
  class SyntaxNode < Treetop::Runtime::SyntaxNode
    attr_accessor :variable, :dependency_id

    def bind_variables(variable_binding)
      # Subclasses should override this
    end

    def track_dependencies(graph)
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

    def track_dependencies(graph)
      params.each{|param| param.track_dependencies(graph) }
      value.track_dependencies(graph)
      graph.add_vertex(self)
      graph.add_edge(value, self)
    end

    def signature
      "#{defined_name}(#{params.map(&:to_s).join(', ')})"
    end

    def to_s
      "#{signature} = #{value}"
    end

    def label
      defined_name
    end
  end


  class ParamDeclaration < SyntaxNode
    def bind_variables(variable_binding)
      self.variable = variable_binding.define(name, self)
    end

    def track_dependencies(graph)
      graph.add_vertex(self)
    end

    def to_s
      "#{type} #{name}"
    end

    def label
      name
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

    def track_dependencies(graph)
      arguments.each{|argument| argument.track_dependencies(graph) }
      graph.add_vertex(self, :function => variable.definition.label, :params => variable.definition.params)
      arguments.each_with_index do |argument, index|
        graph.add_edge(argument, self, :param_index => index)
      end
    end

    def to_s
      "#{name}(#{arguments.map(&:to_s).join(', ')})"
    end
  end


  class VariableReference < SyntaxNode
    def bind_variables(variable_binding)
      self.variable = variable_binding.reference(name, self)
    end

    def track_dependencies(graph)
      if variable.scope.global?
        graph.add_vertex(self) # keep dependencies local to each function, to keep the graph acyclic
      else
        self.dependency_id = variable.definition.dependency_id or raise "untracked variable #{name}"
      end
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
      tree.variables
      tree.dependencies
      tree
    end

    def variables
      return @variables if @variables
      @variables = VariableBinding.new
      bind_variables(@variables)
      if !(undefined = @variables.undefined).empty?
        raise SyntaxError, "undefined variable: #{undefined.map(&:name).join(', ')}"
      end
      @variables
    end

    def dependencies
      return @dependencies if @dependencies
      @dependencies = DependencyGraph.new
      track_dependencies(@dependencies)
      @dependencies
    end

    def bind_variables(variable_binding)
      functions.each{|function| function.bind_variables(variable_binding) }
    end

    def track_dependencies(graph)
      functions.each do |function|
        graph.next_function(function.signature)
        function.track_dependencies(graph)
      end
    end

    def to_s
      functions.map(&:to_s).join('; ')
    end
  end
end
