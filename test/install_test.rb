require 'minitest/autorun'

require_relative '../install'

class InstallTest < Minitest::Test
  def test_service_restores_automatic_fan_control_when_stopped
    service = service_definition(
      ruby_path: '/usr/bin/ruby',
      working_directory: '/opt/fancontrol',
    )

    assert_includes service, 'ExecStart=/usr/bin/ruby fanctrl.rb'
    assert_includes service, 'WorkingDirectory=/opt/fancontrol'
    assert_includes service, 'ExecStop=/usr/bin/ipmitool raw 0x30 0x30 0x01 0x01'
  end
end
