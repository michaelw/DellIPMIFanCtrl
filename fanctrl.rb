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
end

if $PROGRAM_NAME == __FILE__
  loop do
    temp = DellIPMIFanCtrl.get_avg_temp
    manual = temp < DellIPMIFanCtrl::MANUAL_CUTOFF
    fan_speed = DellIPMIFanCtrl.get_fan_speed(temp)

    puts "Temp: #{temp}C -> #{manual ? "Fans: #{fan_speed}%" : "Dell Automated Fan Speed (manual cutoff = #{DellIPMIFanCtrl::MANUAL_CUTOFF})"}"

    DellIPMIFanCtrl.set_manual_fan_ctrl(manual)
    DellIPMIFanCtrl.set_fan_speed(fan_speed) if manual

    sleep DellIPMIFanCtrl::DT
  end
end
