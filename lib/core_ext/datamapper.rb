require 'dm-types/support/dirty_minder'

module DataMapper
  class Property
    module DirtyMinder
      # Work around a bug in Passenger that freezes the nil value.
      # See: https://github.com/datamapper/dm-types/pull/71
      # See: https://code.google.com/p/phusion-passenger/issues/detail?id=1093
      def set!(resource, value)
        # Do not extend non observed value classes
        if Hooker::MUTATION_METHODS.keys.detect { |klass| value.kind_of?(klass) }
          hook_value(resource, value) unless value.kind_of? Hooker
        end
        super
      end
    end
  end
end
