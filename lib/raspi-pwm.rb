module BoolToInteger
  refine TrueClass do
    def to_i
      1
    end
  end

  refine FalseClass do
    def to_i
      0
    end
  end
end

class RaspiPWM
  using BoolToInteger

  LIB_PATH = '/sys/class/pwm'

  DUTY_CYCLE_RANGE = (0..100).freeze

  # A frequency of a generated PWM signal
  attr_reader :frequency

  # The amount of time a digital signal is in `active` state relative to the
  # period of the signal. The value should be between 0..100
  attr_reader :duty_cycle

  # Indicates whether the PWM is enabled or not
  attr_reader :enabled?

  # Base error for all other PWM related errors
  class BaseError < StandardError
  end

  # Exception when trying to initialize with an unknown PWM channel
  class UnknownChannelError < BaseError
  end

  # Exception to handle cases when trying to work with the PWM channel which was
  # already cleaned up
  class NotExportedError < BaseError
  end

  # Exception indicates that an invalid value was passed whether in a method or
  # a property setter
  class InvalidArgumentError < BaseError
  end

  # Initializes a PWM channel
  #
  # @param channel [Integer] a number of a channel
  # @raise [UnknownChannelError] if trying to initialize with the wrong channel number
  def init(channel:)
    @channel = channel.to_i

    verify_channel!

    @frequency = 2
    @duty_cycle = 50
    calculate_ns

    unexport_channel
    export_channel
  end

  # Sets a new frequency value
  #
  # @param new_frequency [Integer] a new frequency value
  # @raise [NotExportedError] if the channel was already cleaned up
  def frequency=(new_frequency)
    raise NotExportedError, "the channel was already unexported" unless exported

    @frequency = new_frequency
    calculate_ns

    File.open("#{LIB_PATH}/pwmchip0/pwm#{channel}/period", 'w') do |file|
      file.write(period_ns)
    end
  end

  # Sets a new duty cycle
  #
  # @param duty_cycle [Integer] a new duty cycle value
  # @raise [NotExportedError] if the channel was already cleaned up
  # @raise [InvalidArgumentError] if an invalid value was set
  def duty_cycle=(new_duty_cycle)
    raise NotExportedError, "the channel was already unexported" unless exported
    raise InvalidArgumentError, "the duty cycle value has to be between 0 and 100" unless DUTY_CYCLE_RANGE.include?(new_duty_cycle)

    @duty_cycle = new_duty_cycle
    calculate_ns

    File.open("#{LIB_PATH}/pwmchip0/pwm#{channel}/duty_cycle", 'w') do |file|
      file.write(duty_cycle_ns)
    end
  end

  # Sets an enableness status of a PWM channel
  #
  # @param value [Boolean] whether true or false meaning enable or disable a channel
  # @raise [NotExportedError] if the channel was already cleaned up
  def enabled=(value)
    raise NotExportedError, "the channel was already unexported" unless exported

    @enabled = value

    File.open("#{LIB_PATH}/pwmchip0/pwm#{channel}/enable", 'w') do |file|
      file.write(@enabled.to_i)
    end
  end

  # Cleans up the channel after completing using it
  def cleanup
    return unless exported

    unexport_channel
  end

  private

  attr_reader :channel, :exported, :period_ns, :duty_cycle_ns

  def calculate_ns
    period_sec = 1 / frequency.to_f
    @period_ns = (period_sec * 10^9).round
    @duty_cycle_ns = (@period_ns * (duty_cycle / 100)).round
  end

  def verify_channel!
    pwm_channels = available_pwm_channels

    return if pwm_channels.include?(channel)

    raise UnknownChannelError, "Unknown PWM channel detected: `#{channel}`! Only #{pwm_channels} are available!"
  end

  def available_pwm_channels
    npwm = File.open("#{LIB_PATH}/pwmchip0/npwm", 'r').read.to_i
    (0..npwm - 1).to_a
  end

  def unexport_channel
    File.open("#{LIB_PATH}/pwmchip0/unexport", 'w') do |file|
      file.write(channel)
    end
  rescue Errno::EINVAL
    # Do nothing - the channel is already unexported
  ensure
    @exported = false
  end

  def export_channel
    File.open("#{LIB_PATH}/pwmchip0/export", 'w') do |file|
      file.write(channel)
    end
    @exported = true
  end
end
