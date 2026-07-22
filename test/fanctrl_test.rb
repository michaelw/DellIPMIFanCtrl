require 'minitest/autorun'
require 'stringio'

require_relative '../fanctrl'

class FanctrlTest < Minitest::Test
  Status = Struct.new(:success?)
  R210II_ERROR = "Unable to send RAW command (channel=0x0 netfn=0x30 lun=0x0 cmd=0x30 rsp=0xcc): Invalid data field in request\n".freeze

  def setup
    DellIPMIFanCtrl.instance_variable_set(:@r210ii_warning_emitted, false)
  end

  def test_manual_control_uses_expected_command_bytes
    runner = recording_runner

    assert DellIPMIFanCtrl.set_manual_fan_ctrl(true, command_runner: runner)
    assert_equal ['ipmitool', 'raw', '0x30', '0x30', '0x01', '0x00'], @command
  end

  def test_fan_speed_uses_integer_hex_byte
    runner = recording_runner

    assert DellIPMIFanCtrl.set_fan_speed(28.9, product_name: 'PowerEdge R730xd', command_runner: runner)
    assert_equal ['ipmitool', 'raw', '0x30', '0x30', '0x02', '0xff', '0x1c'], @command
  end

  def test_successful_speed_write_emits_no_warning
    warning = StringIO.new

    assert DellIPMIFanCtrl.set_fan_speed(
      17,
      product_name: 'PowerEdge R210 II',
      command_runner: recording_runner,
      warning_io: warning,
    )
    assert_empty warning.string
  end

  def test_r210ii_speed_write_tolerates_exact_completion_code_once
    warning = StringIO.new
    runner = recording_runner(success: false, stderr: R210II_ERROR)

    2.times do
      assert DellIPMIFanCtrl.set_fan_speed(
        17,
        product_name: 'PowerEdge R210 II',
        command_runner: runner,
        warning_io: warning,
      )
    end

    assert_equal 1, warning.string.lines.count
    assert_includes warning.string, 'R210 II'
    assert_includes warning.string, '0xcc'
  end

  def test_other_models_keep_exact_speed_write_error
    warning = StringIO.new

    refute DellIPMIFanCtrl.set_fan_speed(
      17,
      product_name: 'PowerEdge R730xd',
      command_runner: recording_runner(success: false, stderr: R210II_ERROR),
      warning_io: warning,
    )
    assert_equal R210II_ERROR, warning.string
  end

  def test_r210ii_keeps_other_speed_write_errors
    warning = StringIO.new
    error = "ipmitool: device unavailable\n"

    refute DellIPMIFanCtrl.set_fan_speed(
      17,
      product_name: 'PowerEdge R210 II',
      command_runner: recording_runner(success: false, stderr: error),
      warning_io: warning,
    )
    assert_equal error, warning.string
  end

  def test_manual_control_errors_are_not_tolerated_on_r210ii
    warning = StringIO.new

    refute DellIPMIFanCtrl.set_manual_fan_ctrl(
      true,
      command_runner: recording_runner(success: false, stderr: R210II_ERROR),
      warning_io: warning,
    )
    assert_equal R210II_ERROR, warning.string
  end

  def test_manual_status_message_formats_temperature_and_applied_fan_duty
    message = DellIPMIFanCtrl.status_message(40.68181818181818, manual: true, fan_speed: 11.36363636363636)

    assert_equal 'Temp: 40.7C -> Fans: 11%', message
  end

  def test_automatic_status_message_formats_temperature
    message = DellIPMIFanCtrl.status_message(65.049, manual: false, fan_speed: 52.3)

    assert_equal 'Temp: 65.0C -> Dell Automated Fan Speed (manual cutoff = 65)', message
  end

  def test_status_message_does_not_expose_floating_point_artifacts
    message = DellIPMIFanCtrl.status_message(48.405, manual: true, fan_speed: 26.810000000000002)

    assert_equal 'Temp: 48.4C -> Fans: 26%', message
  end

  private

  def recording_runner(success: true, stderr: '')
    lambda do |*command|
      @command = command
      ['', stderr, Status.new(success)]
    end
  end
end
