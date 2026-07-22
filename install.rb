def service_definition(ruby_path:, working_directory:)
  <<~SERVICE
    [Unit]
    Description=Dell IPMI Profile Fan Controller

    [Service]
    Type=simple
    Restart=always
    ExecStart=#{ruby_path} fanctrl.rb
    ExecStop=/usr/bin/ipmitool raw 0x30 0x30 0x01 0x01
    WorkingDirectory=#{working_directory}

    [Install]
    WantedBy=multi-user.target

  SERVICE
end

def install
  service = service_definition(
    ruby_path: `which ruby`.strip,
    working_directory: File.absolute_path(File.dirname(__FILE__)),
  )

  File.write('/etc/systemd/system/fanctrl.service', service)
  `systemctl daemon-reload`
  `systemctl enable fanctrl`
  `service fanctrl restart`
  sleep 2
  `service fanctrl status`
end

install if $PROGRAM_NAME == __FILE__
