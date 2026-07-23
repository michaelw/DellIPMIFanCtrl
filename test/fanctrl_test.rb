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

  def test_decrease_controls_have_conservative_defaults
    assert_equal 60, DellIPMIFanCtrl.decrease_interval({})
    assert_equal 1, DellIPMIFanCtrl.decrease_step({})
  end

  def test_decrease_controls_accept_overrides
    env = {
      'FANCTRL_DECREASE_INTERVAL' => '30',
      'FANCTRL_DECREASE_STEP' => '2',
    }

    assert_equal 30, DellIPMIFanCtrl.decrease_interval(env)
    assert_equal 2, DellIPMIFanCtrl.decrease_step(env)
  end

  def test_decrease_interval_rejects_invalid_values
    ['0', '2.5', '-1', 'nope'].each do |value|
      error = assert_raises(ArgumentError) do
        DellIPMIFanCtrl.decrease_interval('FANCTRL_DECREASE_INTERVAL' => value)
      end

      assert_includes error.message, 'FANCTRL_DECREASE_INTERVAL'
      assert_includes error.message, value
    end
  end

  def test_decrease_step_rejects_invalid_values
    ['0', '2.5', '-1', '101', 'nope'].each do |value|
      error = assert_raises(ArgumentError) do
        DellIPMIFanCtrl.decrease_step('FANCTRL_DECREASE_STEP' => value)
      end

      assert_includes error.message, 'FANCTRL_DECREASE_STEP'
      assert_includes error.message, value
    end
  end

  def test_manual_controller_retries_failed_speed_write
    output = StringIO.new
    attempts = 0
    controller = build_controller(output: output) do
      attempts += 1
      attempts > 1
    end

    controller.step(40.0, now: 0)
    assert_nil controller.applied_fan_speed

    controller.step(40.0, now: 5)
    assert_equal 10, controller.applied_fan_speed
    assert_equal 2, attempts
  end

  def test_manual_controller_applies_increases_immediately
    writes = []
    controller = build_controller { |speed| writes << speed; true }

    controller.step(40.0, now: 0)
    controller.step(40.6, now: 5)

    assert_equal [10, 11], writes
    assert_equal 11, controller.applied_fan_speed
  end

  def test_manual_controller_requires_a_persistent_lower_target
    writes = []
    controller = build_controller { |speed| writes << speed; true }

    controller.step(48.0, now: 0)
    controller.step(45.5, now: 5)
    controller.step(45.5, now: 64)

    assert_equal [26], writes
  end

  def test_manual_controller_lowers_one_point_after_a_persistent_window
    writes = []
    controller = build_controller { |speed| writes << speed; true }

    controller.step(48.0, now: 0)
    controller.step(45.5, now: 5)
    controller.step(45.5, now: 65)

    assert_equal [26, 25], writes
  end

  def test_manual_controller_eventually_converges_to_a_stable_curve_target
    writes = []
    controller = build_controller { |speed| writes << speed; true }

    controller.step(48.0, now: 0)
    [5, 65, 125, 185, 245, 305].each do |now|
      controller.step(45.5, now: now)
    end

    assert_equal [26, 25, 24, 23, 22, 21], writes
    assert_equal 21, controller.applied_fan_speed
  end

  def test_manual_controller_uses_the_highest_target_in_the_window
    writes = []
    controller = build_controller { |speed| writes << speed; true }

    controller.step(48.0, now: 0)
    controller.step(45.5, now: 5)
    controller.step(47.5, now: 30)
    controller.step(45.5, now: 65)

    assert_equal [26, 25], writes
  end

  def test_manual_controller_resets_decrease_window_when_target_recovers
    writes = []
    controller = build_controller { |speed| writes << speed; true }

    controller.step(48.0, now: 0)
    controller.step(45.5, now: 5)
    controller.step(48.0, now: 30)
    controller.step(45.5, now: 35)
    controller.step(45.5, now: 94)

    assert_equal [26], writes
  end

  def test_manual_controller_honors_configured_decrease_step
    writes = []
    controller = build_controller(decrease_step: 2) { |speed| writes << speed; true }

    controller.step(48.0, now: 0)
    controller.step(40.0, now: 5)
    controller.step(40.0, now: 65)

    assert_equal [26, 24], writes
  end

  def test_manual_controller_retries_failed_decrease
    writes = []
    fail_decrease_once = true
    controller = build_controller do |speed|
      writes << speed
      if speed == 25 && fail_decrease_once
        fail_decrease_once = false
        false
      else
        true
      end
    end

    controller.step(48.0, now: 0)
    controller.step(45.5, now: 5)
    controller.step(45.5, now: 65)
    assert_equal 26, controller.applied_fan_speed

    controller.step(45.5, now: 70)
    assert_equal [26, 25, 25], writes
    assert_equal 25, controller.applied_fan_speed
  end

  def test_automatic_cutoff_is_immediate_and_manual_reentry_reapplies_target
    modes = []
    writes = []
    controller = build_controller(
      manual_writer: ->(enabled) { modes << enabled; true },
    ) { |speed| writes << speed; true }

    controller.step(64.9, now: 0)
    controller.step(65.0, now: 5)
    controller.step(64.9, now: 10)

    assert_equal [true, false, true], modes
    assert_equal [52, 52], writes
  end

  def test_logging_is_immediate_for_changes_and_quiet_between_heartbeats
    output = StringIO.new
    controller = build_controller(decrease_interval: 600, output: output) { true }

    controller.step(40.0, now: 0)
    controller.step(39.9, now: 5)
    controller.step(39.9, now: 299)
    assert_equal 1, output.string.lines.count

    controller.step(39.9, now: 300)
    assert_equal 2, output.string.lines.count
    assert_includes output.string.lines.last, 'held'
    assert_includes output.string.lines.last, 'target: 9%'
  end

  def test_logging_is_immediate_for_mode_and_applied_speed_changes
    output = StringIO.new
    controller = build_controller(output: output) { true }

    controller.step(40.0, now: 0)
    controller.step(40.6, now: 5)
    controller.step(65.0, now: 10)

    assert_equal 3, output.string.lines.count
    assert_equal 'Temp: 65.0C -> Dell Automated Fan Speed (manual cutoff = 65)', output.string.lines.last.chomp
  end

  private

  def build_controller(
    decrease_interval: 60,
    decrease_step: 1,
    output: StringIO.new,
    manual_writer: ->(_enabled) { true },
    &speed_writer
  )
    DellIPMIFanCtrl::Controller.new(
      decrease_interval: decrease_interval,
      decrease_step: decrease_step,
      output: output,
      manual_writer: manual_writer,
      speed_writer: speed_writer,
    )
  end

  def recording_runner(success: true, stderr: '')
    lambda do |*command|
      @command = command
      ['', stderr, Status.new(success)]
    end
  end
end
