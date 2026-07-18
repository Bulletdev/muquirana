class Rule::ActionExecutor
  TYPES = [ "select", "function", "text" ]

  def initialize(rule)
    @rule = rule
  end

  def key
    self.class.name.demodulize.underscore
  end

  def label
    key.humanize
  end

  def type
    "function"
  end

  def options
    nil
  end

  def execute(scope, value: nil, ignore_attribute_locks: false)
    raise NotImplementedError, "Action executor #{self.class.name} must implement #execute"
  end

  def as_json
    {
      type: type,
      key: key,
      label: label,
      options: options
    }
  end

  protected
    # Runs the block for each resource in the scope and returns the number of
    # resources that were actually modified. Modification is detected via
    # ActiveRecord's `previous_changes` (checking the resource and, when present,
    # its associated entry), since our enrichment writes may be no-ops when a
    # value is already set or the attribute is locked.
    def count_modified_resources(scope)
      modified_count = 0

      scope.each do |resource|
        yield resource

        was_modified = resource.previous_changes.any?

        if !was_modified && resource.respond_to?(:entry)
          entry = resource.entry
          was_modified = entry&.previous_changes&.any? || false
        end

        modified_count += 1 if was_modified
      end

      modified_count
    end

  private
    attr_reader :rule

    def family
      rule.family
    end
end
