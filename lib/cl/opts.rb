require 'cl/opt'

class Cl
  class Opts
    include Enumerable, Regex

    def define(const, *args, &block)
      opts = args.last.is_a?(Hash) ? args.pop : {}
      strs = args.select { |arg| arg.start_with?('-') }
      opts[:description] = args.-(strs).first

      opt = Opt.new(strs, opts, block)
      opt.define(const)
      self << opt
    end

    def apply(cmd, opts)
      return opts if opts[:help]
      cmd.deprecations = deprecations(cmd, opts)
      opts = with_defaults(cmd, opts)
      opts = downcase(opts)
      opts = cast(opts)
      opts = taint(opts)
      validate(cmd, opts)
      opts
    end

    def <<(opt)
      delete(opt)
      # keep the --help option at the end for help output
      opts.empty? ? opts << opt : opts.insert(-2, opt)
    end

    def [](key)
      opts.detect { |opt| opt.name == key }
    end

    def each(&block)
      opts.each(&block)
    end

    def delete(opt)
      opts.delete(opts.detect { |o| o.strs == opt.strs })
    end

    def to_a
      opts
    end

    attr_writer :opts

    def opts
      @opts ||= []
    end

    def deprecated
      map(&:deprecated).flatten.compact
    end

    def dup
      super.tap { |obj| obj.opts = opts.dup }
    end

    private

      def deprecations(cmd, opts)
        defs = cmd.class.opts.select(&:deprecated?)
        defs = defs.select { |opt| opts.key?(opt.deprecated[0]) }
        defs.map(&:deprecated).to_h
      end

      def validate(cmd, opts)
        validate_requireds(cmd, opts)
        validate_required(opts)
        validate_requires(opts)
        validate_range(opts)
        validate_format(opts)
        validate_enum(opts)
      end

      def validate_requireds(cmd, opts)
        opts = missing_requireds(cmd, opts)
        raise RequiredsOpts.new(opts) if opts.any?
      end

      def validate_required(opts)
        opts = missing_required(opts)
        # make sure we do not accept unnamed required options
        raise RequiredOpts.new(opts.map(&:name)) if opts.any?
      end

      def validate_requires(opts)
        opts = missing_requires(opts)
        raise RequiresOpts.new(invert(opts)) if opts.any?
      end

      def validate_range(opts)
        opts = out_of_range(opts)
        raise OutOfRange.new(opts) if opts.any?
      end

      def validate_format(opts)
        opts = invalid_format(opts)
        raise InvalidFormat.new(opts) if opts.any?
      end

      def validate_enum(opts)
        opts = unknown_values(opts)
        raise UnknownValues.new(opts) if opts.any?
      end

      def missing_requireds(cmd, opts)
        opts = cmd.class.required.map do |alts|
          alts if alts.none? { |alt| Array(alt).all? { |key| opts.key?(key) } }
        end.compact
      end

      def missing_required(opts)
        select(&:required?).select { |opt| !opts.key?(opt.name) }
      end

      def missing_requires(opts)
        select(&:requires?).map do |opt|
          next unless opts.key?(opt.name)
          missing = opt.requires.select { |key| !opts.key?(key) }
          [opt.name, missing] if missing.any?
        end.compact
      end

      def out_of_range(opts)
        self.opts.map do |opt|
          next unless value = opts[opt.name]
          range = only(opt.opts, :min, :max)
          [opt.name, compact(range)] if out_of_range?(range, value)
        end.compact
      end

      def out_of_range?(range, value)
        min, max = range.values_at(:min, :max)
        min && value < min || max && value > max
      end

      def invalid_format(opts)
        select(&:format?).map do |opt|
          value = opts[opt.name]
          [opt.name, opt.format] if value && !opt.formatted?(value)
        end.compact
      end

      def unknown_values(opts)
        select(&:enum?).map do |opt|
          value = opts[opt.name]
          next unless value && !opt.known?(value)
          known = opt.enum.map { |str| format_regex(str) }
          [opt.name, value, known]
        end.compact
      end

      def with_defaults(cmd, opts)
        select(&:default?).inject(opts) do |opts, opt|
          next opts if opts.key?(opt.name)
          value = opt.default
          value = resolve(cmd, opts, value) if value.is_a?(Symbol)
          opts.merge(opt.name => value)
        end
      end

      def resolve(cmd, opts, key)
        opts[key] || cmd.respond_to?(key) && cmd.send(key)
      end

      def downcase(opts)
        select(&:downcase?).inject(opts) do |opts, opt|
          next opts unless value = opts[opt.name]
          opts.merge(opt.name => value.to_s.downcase)
        end
      end

      def cast(opts)
        opts.map do |key, value|
          [key, self[key] ? self[key].cast(value) : value]
        end.to_h
      end

      def taint(opts)
        opts.map do |key, value|
          [key, self[key] && self[key].secret? ? value.taint : value]
        end.to_h
      end

      def compact(hash, *keys)
        hash.reject { |_, value| value.nil? }.to_h
      end

      def only(hash, *keys)
        hash.select { |key, _| keys.include?(key) }.to_h
      end

      def invert(hash)
        hash.map { |key, obj| Array(obj).map { |obj| [obj, key] } }.flatten(1).to_h
      end
  end
end
