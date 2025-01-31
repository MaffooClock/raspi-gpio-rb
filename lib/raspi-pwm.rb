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

# A simple wrapper around the hardware PWM interface
#
# For details, see the kernel documentation[https://www.kernel.org/doc/Documentation/pwm.txt]
#
# @author sergio1990
#
# @example Common usage
#   pwm = RaspiPWM.new(channel: 0)
#   pwm.frequency = 100
#   pwm.duty_cycle = 75
#   pwm.enabled = true
#
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
  attr_reader :enabled

  # Base error for all other PWM related errors
  class BaseError < StandardError
  end

  # Exception when trying to initialize with an unknown PWM chip
  class UnknownChipError < BaseError
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
  # @param chip [Integer] a number of a PWM chip, default is 0
  # @param channel [Integer] a number of a channel
  # @raise [UnknownChipError] if trying to initialize with the wrong chip number
  # @raise [UnknownChannelError] if trying to initialize with the wrong channel number
  def initialize(chip: 0, channel:)
    @chip = chip
    @channel = channel.to_i

    @chip_path = "#{LIB_PATH}/pwmchip#{chip}"
    @channel_path = "#{LIB_PATH}/pwmchip#{chip}/pwm#{channel}"

    verify_chip!
    verify_channel!

    @frequency = 2
    @duty_cycle = 50
    calculate_ns

    unexport_channel
    export_channel

    @enabled = false
  end

  # Sets a new frequency value
  #
  # @param new_frequency [Integer] a value in amount of Hz
  # @raise [NotExportedError] if the channel was already cleaned up
  def frequency=(new_frequency)
    raise NotExportedError, "the channel was already unexported" unless exported

    @frequency = new_frequency
    calculate_ns
    write_pwm_parameters
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
    write_pwm_parameters
  end

  # Sets an enableness status of a PWM channel
  #
  # @param value [Boolean] whether true or false meaning enable or disable a channel
  # @raise [NotExportedError] if the channel was already cleaned up
  def enabled=(value)
    raise NotExportedError, "the channel was already unexported" unless exported

    @enabled = value

    File.open("#{channel_path}/enable", 'w') do |file|
      file.write(@enabled.to_i)
    end
  end

  # Cleans up the channel after completing using it
  def cleanup
    return unless exported

    enabled = false
    unexport_channel
  end

  private

  attr_reader :chip, :channel, :exported, :period_ns, :duty_cycle_ns
  attr_reader :chip_path, :channel_path

  def calculate_ns
    period_sec = 1 / frequency.to_f
    @period_ns = (period_sec * 10**9).round
    @duty_cycle_ns = (@period_ns * (duty_cycle / 100.0)).round
  end

  def write_pwm_parameters
    # The duty_cycle must always be lower than period. If initializing the PWM
    # only once we're good, but if we'd like to change values over time there
    # will be cases when we set the period value which is lower then the duty
    # cycle one and vise versa.
    # Hence, in order to eliminate any issues (🤞) we want to run the next
    # sequence of commands:
    # 1. disable PWM
    # 2. set the duty cycle to 0 (zero)
    # 3. set the period with a new value
    # 4. set the duty cycle with a new value
    # 5. enable PWM again
    #
    # In this case, we ensure that the duty cycle is always lower than period

    was_enabled_before = enabled
    enabled = false if was_enabled_before

    File.open("#{channel_path}/duty_cycle", 'w') do |file|
      file.write(0)
    end

    File.open("#{channel_path}/period", 'w') do |file|
      file.write(period_ns)
    end

    File.open("#{channel_path}/duty_cycle", 'w') do |file|
      file.write(duty_cycle_ns)
    end

    enabled = true if was_enabled_before
  end

  def verify_chip!
    return if Dir.exist?(chip_path)

    raise UnknownChipError, "Unknown PWM chip detected: `#{chip}`!"
  end

  def verify_channel!
    pwm_channels = available_pwm_channels

    return if pwm_channels.include?(channel)

    raise UnknownChannelError, "Unknown PWM channel detected: `#{channel}`! Only #{pwm_channels} are available!"
  end

  def available_pwm_channels
    npwm = File.open("#{chip_path}/npwm", 'r').read.to_i
    (0..npwm - 1).to_a
  end

  def unexport_channel
    File.open("#{chip_path}/unexport", 'w') do |file|
      file.write(channel)
    end
  rescue Errno::ENODEV
    # Do nothing - the channel is already unexported
  ensure
    @exported = false
  end

  def export_channel
    File.open("#{chip_path}/export", 'w') do |file|
      file.write(channel)
    end
    @exported = true
  end
end
