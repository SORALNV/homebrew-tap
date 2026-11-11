class Myvnc < Formula
  desc "Live screen viewer server for macOS (MJPEG over HTTP, token auth, Tailscale-only bind)"
  homepage "https://github.com/SORALNV/MyVNC"
  url "https://github.com/SORALNV/MyVNC/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "75d04606885054a3f7af84aa3fbd3a6000a4f06bedae66f73ae721071338f14d"
  version "0.1.0"

  def install
    libexec.install "server.py", "index.html"
    (bin/"myvnc").write <<~EOS
      #!/bin/bash
      exec /usr/bin/python3 "#{libexec}/server.py" "$@"
    EOS
  end

  def caveats
    <<~EOS
      Start the service and get the viewer URL (token included):

        brew services start SORALNV/tap/myvnc
        grep "viewer URL" #{var}/log/myvnc.out.log

      The server generates #{etc}/myvnc/config.json on first start (chmod 600).
      It binds to the Tailscale IP only (config: bind_ip) and requires cua-driver
      for screen capture (config: cua_driver, default ~/.local/bin/cua-driver).

      Open the viewer URL in a browser on any tailnet device.
    EOS
  end

  def plist
    <<~EOS
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>ProgramArguments</key>
        <array>
          <string>/usr/bin/python3</string>
          <string>#{libexec}/server.py</string>
        </array>
        <key>EnvironmentVariables</key>
        <dict>
          <key>MYVNC_CONFIG</key>
          <string>#{etc}/myvnc/config.json</string>
          <key>MYVNC_FRAME_DIR</key>
          <string>#{var}/myvnc/frames</string>
        </dict>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>ThrottleInterval</key>
        <integer>10</integer>
        <key>StandardOutPath</key>
        <string>#{var}/log/myvnc.out.log</string>
        <key>StandardErrorPath</key>
        <string>#{var}/log/myvnc.err.log</string>
      </dict>
      </plist>
    EOS
  end

  test do
    require "json"
    require "securerandom"

    port = free_port
    token = SecureRandom.hex(16)
    config = {
      "bind_ip" => "127.0.0.1",
      "port" => port,
      "token" => token,
      "interval_sec" => 3600,
      "max_image_dimension" => 320,
      "cua_driver" => "/usr/bin/true",
    }
    (testpath/"config.json").write(JSON.pretty_generate(config))

    env = {
      "MYVNC_CONFIG" => (testpath/"config.json").to_s,
      "MYVNC_FRAME_DIR" => (testpath/"frames").to_s,
    }
    pid = Process.spawn(env, "/usr/bin/python3", libexec/"server.py")
    begin
      uri = "http://127.0.0.1:#{port}"
      health = nil
      30.times do
        sleep 0.3
        begin
          health = shell_output("curl -fsS '#{uri}/health?token=#{token}'", 0)
          break
        rescue
          nil
        end
      end
      assert health, "server did not come up"
      assert_match(/"frames"/, health)

      code = shell_output("curl -s -o /dev/null -w '%{http_code}' #{uri}/health").strip
      assert_equal "401", code

      page = shell_output("curl -fsS '#{uri}/?token=#{token}'")
      assert_match(%r{/stream\?token=}, page)
    ensure
      Process.kill("TERM", pid) rescue nil
      Process.wait(pid) rescue nil
    end
  end
end
