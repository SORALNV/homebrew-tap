class Myvnc < Formula
  desc "Live screen viewer server (MJPEG over HTTP, token auth)"
  homepage "https://github.com/SORALNV/MyVNC"
  url "https://github.com/SORALNV/MyVNC/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "75d04606885054a3f7af84aa3fbd3a6000a4f06bedae66f73ae721071338f14d"

  def install
    libexec.install "server.py", "index.html", "ime.swift"
    # session-helper (IME sync / lock state) — optional, needs Xcode CLT
    if which("swiftc")
      system "swiftc", "-O", libexec/"ime.swift", "-o", libexec/"session-helper"
    end
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
      It binds to the Tailscale IP only (config: bind_ip) and needs cua-driver
      for screen capture (config: cua_driver, default ~/.local/bin/cua-driver).
    EOS
  end

  service do
    run ["/usr/bin/python3", opt_libexec/"server.py"]
    environment_variables MYVNC_CONFIG:    etc/"myvnc/config.json",
                          MYVNC_FRAME_DIR: var/"myvnc/frames"
    keep_alive true
    process_type :background
    log_path var/"log/myvnc.out.log"
    error_log_path var/"log/myvnc.err.log"
    working_dir opt_libexec
  end

  test do
    require "json"
    require "securerandom"

    port = free_port
    token = SecureRandom.hex(16)
    config = {
      "bind_ip"             => "127.0.0.1",
      "port"                => port,
      "token"               => token,
      "interval_sec"        => 3600,
      "max_image_dimension" => 320,
      "cua_driver"          => "/usr/bin/true",
    }
    (testpath/"config.json").write(JSON.pretty_generate(config))

    env = {
      "MYVNC_CONFIG"    => (testpath/"config.json").to_s,
      "MYVNC_FRAME_DIR" => (testpath/"frames").to_s,
    }
    pid = Process.spawn(env, "/usr/bin/python3", libexec/"server.py")
    begin
      uri = "http://127.0.0.1:#{port}"
      # curl handles the startup wait itself (retries on connection refused)
      health = shell_output(
        "curl -fsS --retry 20 --retry-delay 1 --retry-connrefused '#{uri}/health?token=#{token}'",
      )
      assert_match(/"frames"/, health)

      body = shell_output("curl -s #{uri}/health")
      assert_match(/401/, body)

      page = shell_output("curl -fsS '#{uri}/?token=#{token}'")
      assert_match(%r{/stream\?token=}, page)
    ensure
      begin
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue
        nil
      end
    end
  end
end
