require 'rubygems'
require 'treetop'

%w(parsetree variable_binding dependency_graph).each do |filename|
  require File.join(File.dirname(__FILE__), 'flowquery', filename)
end

Treetop.load(File.join(File.dirname(__FILE__), 'flowquery', 'grammar.treetop'))
