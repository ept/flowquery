module Flowquery
  class DependencyGraph
    def initialize
      @dependency_ids = 0
      @functions = []
    end

    def next_dependency_id
      @dependency_ids += 1
    end

    def next_function(label)
      @function = {
        :label => label,
        :vertices => {},
        :forward_edges => {},
        :backward_edges => {}
      }
      @functions << @function
    end

    def add_vertex(vertex, options={})
      vertex.dependency_id ||= next_dependency_id
      @function[:vertices][vertex.dependency_id] = {:vertex => vertex}.merge(options)
    end

    def add_edge(from, to, options={})
      raise "Edge start is not a vertex: #{from.inspect}" unless from.dependency_id
      raise "Edge end is not a vertex: #{to.inspect}" unless to.dependency_id
      @function[:forward_edges][from.dependency_id] ||= []
      @function[:forward_edges][from.dependency_id] << {:to => to.dependency_id}.merge(options)
      @function[:backward_edges][to.dependency_id] ||= []
      @function[:backward_edges][to.dependency_id] << {:from => from.dependency_id}.merge(options)
    end

    def to_graphviz
      output = "digraph G {\n"#{vertices_to_graphviz}\n#{edges_to_graphviz}\n}\n"
      output << "    node [#{options(:shape => :box)}];\n"
      @functions.each_with_index do |function, index|
        output << "\n    subgraph cluster#{index} {\n"
        output << "        #{options(:label => function[:label])};\n"
        output << "        #{options(:color => :gray)};\n"
        output << vertices_to_graphviz(function)
        output << edges_to_graphviz(function)
        output << "    }\n"
      end
      output << "}\n"
      output
    end

    def vertices_to_graphviz(function)
      function[:vertices].map do |id, vertex_hash|
        vertex = vertex_hash[:vertex]
        label = vertex.respond_to?(:label) ? vertex.label : vertex.to_s

        if vertex_hash[:params]
          html = '<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="4"><TR>'
          html << %Q(<TD>#{h(vertex_hash[:function])}</TD>)
          vertex_hash[:params].each_with_index do |param, index|
            html << %Q(<TD PORT="#{index}">#{h(param)}</TD>)
          end
          html << %Q(</TR><TR><TD COLSPAN="#{vertex_hash[:params].size + 1}">#{h(label)}</TD></TR></TABLE>)
          "        v#{id} [shape=none, margin=0, label=<#{html}>];\n"
        else
          "        v#{id} [#{options(:label => label)}];\n"
        end
      end.join
    end

    def edges_to_graphviz(function)
      function[:forward_edges].map do |from, to_list|
        to_list.map do |to|
          head = "v#{to[:to]}"
          head << ":#{to[:param_index]}" if to[:param_index]
          "        v#{from} -> #{head};\n"
        end
      end.flatten(1).join
    end

    # Escaped for graphviz output
    def options(hash)
      hash.map do |key, value|
        quoted_value = value.to_s.gsub('"', '\\"')
        %Q(#{key}="#{quoted_value}")
      end.join(', ')
    end

    # HTML escaping
    def h(text)
      text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end
  end
end
