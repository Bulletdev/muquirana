class Period
  include ActiveModel::Validations, Comparable

  class InvalidKeyError < StandardError; end

  attr_reader :key, :start_date, :end_date

  validates :start_date, :end_date, presence: true, if: -> { PERIODS[key].nil? }
  validates :key, presence: true, if: -> { start_date.nil? || end_date.nil? }
  validate :must_be_valid_date_range

  # As chaves ("last_30_days" etc) sao identificadores: ficam persistidas em
  # users.default_period e sao validadas por User. Nao renomear.
  #
  # Os rotulos (label, label_short, comparison_label) sairam deste hash e vivem
  # em config/locales/models/period/*.yml -- ver #label e #comparison_label.
  PERIODS = {
    "last_day" => {
      date_range: -> { [ 1.day.ago.to_date, Date.current ] }
    },
    "current_week" => {
      date_range: -> { [ Date.current.beginning_of_week, Date.current ] }
    },
    "last_7_days" => {
      date_range: -> { [ 7.days.ago.to_date, Date.current ] }
    },
    "current_month" => {
      date_range: -> { [ Date.current.beginning_of_month, Date.current ] }
    },
    "last_30_days" => {
      date_range: -> { [ 30.days.ago.to_date, Date.current ] }
    },
    "last_90_days" => {
      date_range: -> { [ 90.days.ago.to_date, Date.current ] }
    },
    "current_year" => {
      date_range: -> { [ Date.current.beginning_of_year, Date.current ] }
    },
    "last_365_days" => {
      date_range: -> { [ 365.days.ago.to_date, Date.current ] }
    },
    "last_5_years" => {
      date_range: -> { [ 5.years.ago.to_date, Date.current ] }
    }
  }

  class << self
    def from_key(key)
      unless PERIODS.key?(key)
        raise InvalidKeyError, "Invalid period key: #{key}"
      end

      start_date, end_date = PERIODS[key].fetch(:date_range).call

      new(key: key, start_date: start_date, end_date: end_date)
    end

    def custom(start_date:, end_date:)
      new(start_date: start_date, end_date: end_date)
    end

    def all
      PERIODS.map { |key, period| from_key(key) }
    end

    def as_options
      all.map { |period| [ period.label_short, period.key ] }
    end
  end

  PERIODS.each do |key, period|
    define_singleton_method(key) do
      from_key(key)
    end
  end

  def initialize(start_date: nil, end_date: nil, key: nil)
    @key = key
    @start_date = start_date
    @end_date = end_date
    validate!
  end

  def <=>(other)
    [ start_date, end_date ] <=> [ other.start_date, other.end_date ]
  end

  def date_range
    start_date..end_date
  end

  def days
    (end_date - start_date).to_i + 1
  end

  def within?(other)
    start_date >= other.start_date && end_date <= other.end_date
  end

  def interval
    if days > 366
      "1 week"
    else
      "1 day"
    end
  end

  # Os rotulos vivem em config/locales/models/period/*.yml e nao no hash PERIODS
  # (que ficou so com date_range). As chaves de PERIODS continuam identificadores
  # -- sao persistidas em users.default_period e validadas em User.
  def label
    if key_metadata
      I18n.t("periods.#{key}.label")
    else
      I18n.t("periods.custom.label")
    end
  end

  def label_short
    if key_metadata
      I18n.t("periods.#{key}.label_short")
    else
      I18n.t("periods.custom.label_short")
    end
  end

  def comparison_label
    if key_metadata
      I18n.t("periods.#{key}.comparison_label")
    else
      I18n.t(
        "periods.custom.comparison_label",
        start_date: I18n.l(start_date, format: :long),
        end_date: I18n.l(end_date, format: :long)
      )
    end
  end

  private
    def key_metadata
      @key_metadata ||= PERIODS[key]
    end

    def must_be_valid_date_range
      return if start_date.nil? || end_date.nil?
      unless start_date.is_a?(Date) && end_date.is_a?(Date)
        errors.add(:start_date, "must be a valid date, got #{start_date.inspect}")
        errors.add(:end_date, "must be a valid date, got #{end_date.inspect}")
        return
      end

      errors.add(:start_date, "must be before end date") if start_date > end_date
    end
end
