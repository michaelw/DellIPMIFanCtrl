require 'open3'

module DellIPMIFanCtrl
  # Each line: [ temp C, fan speed % ]
  CURVE = [
    [0, 0],
    [10, 0],
    [30, 5],
    [40, 10],
    [50, 30],
    [70, 60],
    [80, 100]
  ].freeze

  MANUAL_CUTOFF = 65  # When to disable OS fan control
  DT = 5              # Check every DT seconds
  DEFAULT_DEADBAND = 5
  STATUS_LOG_INTERVAL = 300
  R210II_PRODUCT_NAME = 'PowerEdge R210 II'.freeze
  R210II_SPEED_ERROR = /rsp=0xcc\).*Invalid data field in request/m.freeze

  module_function

  def get_avg_temp
    `sensors -u`.scan(/temp[0-9]+_input:\s([0-9.]+)/).flatten.map(&:to_f).instance_eval { reduce(:+) / size.to_f }
  end

  def get_fan_speed(temp)
    i = 0
    power = 100
    while i < (CURVE.size - 1)
      a = CURVE[i]
      b = CURVE[i + 1]

      if temp >= a[0] && temp <= b[0]
        power = a[1] + (temp - a[0]) * (b[1] - a[1]) / (b[0] - a[0])
        break
      end

      i += 1
    end

    power
  end

  def deadband(env = ENV)
    value = env.fetch('FANCTRL_DEADBAND', DEFAULT_DEADBAND.to_s)
    parsed = Integer(value, 10)
    return parsed if parsed.between?(0, 100)

    raise ArgumentError
  rescue ArgumentError
    raise ArgumentError, "FANCTRL_DEADBAND must be a whole number from 0 to 100 (got #{value.inspect})"
  end

  def speed_update_required?(target:, applied:, deadband:)
    return true if applied.nil?
    return true if target > applied

    target < applied && (applied - target) >= deadband
  end

  def status_message(temp, manual:, fan_speed:, target_fan_speed: nil)
    fan_status = if manual
                   if fan_speed.nil?
                     "Fans: unknown (target: #{target_fan_speed.to_i}%)"
                   elsif !target_fan_speed.nil? && target_fan_speed.to_i != fan_speed.to_i
                     "Fans: #{fan_speed.to_i}% (target: #{target_fan_speed.to_i}%, held)"
                   else
                     "Fans: #{fan_speed.to_i}%"
                   end
                 else
                   "Dell Automated Fan Speed (manual cutoff = #{MANUAL_CUTOFF})"
                 end

    format('Temp: %.1fC -> %s', temp, fan_status)
  end

  def product_name
    File.read('/sys/class/dmi/id/product_name').delete("\0").strip
  rescue SystemCallError
    nil
  end

  def set_fan_speed(speed, product_name: self.product_name, command_runner: Open3.method(:capture3), warning_io: $stderr)
    command = ['ipmitool', 'raw', '0x30', '0x30', '0x02', '0xff', "0x#{speed.to_i.to_s(16)}"]
    _stdout, stderr, status = command_runner.call(*command)

    return true if status.success?

    if product_name == R210II_PRODUCT_NAME && stderr.match?(R210II_SPEED_ERROR)
      unless @r210ii_warning_emitted
        warning_io.puts 'PowerEdge R210 II returned 0xcc after a fan-speed write; treating the known response as applied'
        @r210ii_warning_emitted = true
      end
      return true
    end

    warning_io.write(stderr)
    false
  end

  def set_manual_fan_ctrl(enable, command_runner: Open3.method(:capture3), warning_io: $stderr)
    command = ['ipmitool', 'raw', '0x30', '0x30', '0x01', enable ? '0x00' : '0x01']
    _stdout, stderr, status = command_runner.call(*command)

    warning_io.write(stderr) unless status.success?
    status.success?
  end

  class Controller
    attr_reader :applied_fan_speed, :manual

    def initialize(deadband:, output: $stdout, manual_writer: nil, speed_writer: nil)
      @deadband = deadband
      @output = output
      @manual_writer = manual_writer || DellIPMIFanCtrl.method(:set_manual_fan_ctrl)
      @speed_writer = speed_writer || DellIPMIFanCtrl.method(:set_fan_speed)
      @applied_fan_speed = nil
      @manual = nil
      @last_status_at = nil
    end

    def step(temp, now: Process.clock_gettime(Process::CLOCK_MONOTONIC))
      desired_manual = temp < MANUAL_CUTOFF
      target = DellIPMIFanCtrl.get_fan_speed(temp).to_i
      previous_manual = @manual
      mode_changed = false
      speed_changed = false

      if @manual_writer.call(desired_manual)
        @manual = desired_manual
        mode_changed = previous_manual != @manual
        @applied_fan_speed = nil if mode_changed
      end

      if desired_manual && DellIPMIFanCtrl.speed_update_required?(
        target: target,
        applied: @applied_fan_speed,
        deadband: @deadband,
      ) && @speed_writer.call(target)
        speed_changed = @applied_fan_speed != target
        @applied_fan_speed = target
      end

      log_status(temp, target, desired_manual, now) if status_due?(mode_changed || speed_changed, now)
    end

    private

    def status_due?(state_changed, now)
      state_changed || @last_status_at.nil? || (now - @last_status_at) >= STATUS_LOG_INTERVAL
    end

    def log_status(temp, target, desired_manual, now)
      reported_manual = @manual.nil? ? desired_manual : @manual
      @output.puts DellIPMIFanCtrl.status_message(
        temp,
        manual: reported_manual,
        fan_speed: @applied_fan_speed,
        target_fan_speed: target,
      )
      @last_status_at = now
    end
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.sync = true
  controller = DellIPMIFanCtrl::Controller.new(deadband: DellIPMIFanCtrl.deadband)

  loop do
    temp = DellIPMIFanCtrl.get_avg_temp
    controller.step(temp)
    sleep DellIPMIFanCtrl::DT
  end
end
