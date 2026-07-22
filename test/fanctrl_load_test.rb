require 'minitest/autorun'
require 'rbconfig'
require 'tmpdir'
require 'timeout'

class FanctrlLoadTest < Minitest::Test
  def test_requiring_fanctrl_does_not_start_controller_loop
    fanctrl = File.expand_path('../fanctrl.rb', __dir__)
    completed = false
    pid = nil

    Dir.mktmpdir do |dir|
      write_executable(dir, 'sensors', "#!/bin/sh\necho 'temp1_input: 40.0'\n")
      write_executable(dir, 'ipmitool', "#!/bin/sh\nexit 0\n")
      pid = Process.spawn(
        { 'PATH' => "#{dir}:#{ENV.fetch('PATH')}" },
        RbConfig.ruby,
        '-e',
        "require #{fanctrl.inspect}",
        out: File::NULL,
        err: File::NULL,
      )

      Timeout.timeout(1) do
        _pid, status = Process.wait2(pid)
        completed = status.success?
      end
    end

    assert completed, 'requiring fanctrl.rb started the controller loop'
  ensure
    begin
      Process.kill('TERM', pid) if pid
      Process.wait(pid) if pid
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end

  private

  def write_executable(dir, name, contents)
    path = File.join(dir, name)
    File.write(path, contents)
    File.chmod(0o755, path)
  end
end
