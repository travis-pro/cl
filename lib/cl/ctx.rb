require 'forwardable'
require 'cl/config'
require 'cl/ui'

module Cl
  class Ctx
    extend Forwardable

    def_delegators :ui, :puts, :stdout, :announce, :info, :notice, :warn,
      :error, :success, :cmd

    attr_accessor :config, :ui

    def initialize(name, opts = {})
      @config = Config.new(name)
      @ui = Ui.new(self, opts)
    end

    def abort(str)
      fail(str) if test?
      ui.error(str)
      exit 1
    end

    def test?
      ENV['ENV'] == 'test'
    end
  end
end
