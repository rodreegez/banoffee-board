require "etc"
require "json"
require "rack"
require "shellwords"

APP_BOOTED_AT = Time.now.utc
REFRESH_SECONDS = 30

UNITS = %w[B KiB MiB GiB TiB].freeze


def h(value)
  Rack::Utils.escape_html(value.to_s)
end

def format_bytes(bytes)
  value = bytes.to_f
  unit = UNITS.first

  UNITS.each do |candidate|
    unit = candidate
    break if value < 1024.0 || candidate == UNITS.last

    value /= 1024.0
  end

  if value >= 100
    "#{value.round} #{unit}"
  elsif value >= 10
    format("%.1f %s", value, unit)
  else
    format("%.2f %s", value, unit)
  end
end

def format_duration(total_seconds)
  seconds = total_seconds.to_i
  parts = []

  {
    "d" => 86_400,
    "h" => 3_600,
    "m" => 60,
    "s" => 1
  }.each do |label, span|
    next if seconds < span && parts.empty? && label != "s"

    amount, seconds = seconds.divmod(span)
    next if amount.zero? && !parts.empty? && label == "s"
    next if amount.zero?

    parts << "#{amount}#{label}"
    break if parts.length >= 3
  end

  parts.empty? ? "0s" : parts.join(" ")
end

def safe_read(path)
  File.read(path)
rescue StandardError
  nil
end

def load_stats
  values = safe_read("/proc/loadavg")&.split&.first(3)&.map(&:to_f) || [0.0, 0.0, 0.0]
  cores = Etc.nprocessors
  pressure = cores.positive? ? (values.first / cores) : 0.0

  mood = case pressure
         when 0...0.35 then "idle"
         when 0.35...0.7 then "steady"
         when 0.7...1.0 then "busy"
         else "hot"
         end

  {
    one: values[0] || 0.0,
    five: values[1] || 0.0,
    fifteen: values[2] || 0.0,
    cores: cores,
    mood: mood,
    pressure_percent: (pressure * 100).round(1)
  }
rescue StandardError
  {
    one: 0.0,
    five: 0.0,
    fifteen: 0.0,
    cores: 0,
    mood: "unknown",
    pressure_percent: 0.0
  }
end

def memory_stats
  info = {}

  File.foreach("/proc/meminfo") do |line|
    key, value = line.split(":", 2)
    next unless key && value

    info[key] = value[/\d+/].to_i
  end

  total = info.fetch("MemTotal", 0) * 1024
  available = info.fetch("MemAvailable", info.fetch("MemFree", 0)) * 1024
  used = [total - available, 0].max
  used_percent = total.positive? ? ((used.to_f / total) * 100).round(1) : 0.0

  {
    total: total,
    used: used,
    available: available,
    used_percent: used_percent
  }
rescue StandardError
  {
    total: 0,
    used: 0,
    available: 0,
    used_percent: 0.0
  }
end

def disk_stats(path = "/")
  output = `df -P -B1 #{Shellwords.escape(path)} 2>/dev/null`
  line = output.lines[1]
  fields = line&.split(/\s+/) || []

  total = fields[1].to_i
  used = fields[2].to_i
  available = fields[3].to_i
  used_percent = fields[4].to_s.delete("%").to_f

  {
    path: path,
    total: total,
    used: used,
    available: available,
    used_percent: used_percent
  }
rescue StandardError
  {
    path: path,
    total: 0,
    used: 0,
    available: 0,
    used_percent: 0.0
  }
end

def uptime_stats
  uptime_seconds = safe_read("/proc/uptime")&.split&.first.to_f
  {
    host_seconds: uptime_seconds.to_i,
    app_seconds: (Time.now.utc - APP_BOOTED_AT).to_i
  }
rescue StandardError
  {
    host_seconds: 0,
    app_seconds: (Time.now.utc - APP_BOOTED_AT).to_i
  }
end

def collect_stats
  now = Time.now.utc
  hostname = ENV["HOSTNAME"] || `hostname`.strip
  version = ENV["APP_VERSION"] || "dev"

  {
    hostname: hostname,
    version: version,
    repo_url: ENV["REPO_URL"] || "https://github.com/rodreegez/banoffee-board",
    now: now,
    load: load_stats,
    memory: memory_stats,
    disk: disk_stats,
    uptime: uptime_stats,
    health: "OK"
  }
end

def page(stats)
  load = stats[:load]
  memory = stats[:memory]
  disk = stats[:disk]
  uptime = stats[:uptime]
  now = stats[:now]

  load_summary = format("%.2f %.2f %.2f", load[:one], load[:five], load[:fifteen])
  headline = "system nominal :: load #{load[:mood]} :: memory #{memory[:used_percent]}% :: disk #{disk[:used_percent]}%"

  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="refresh" content="#{REFRESH_SECONDS}">
        <title>Banoffee Board</title>
        <style>
          :root {
            --bg: #020703;
            --panel: rgba(4, 24, 9, 0.9);
            --panel-soft: rgba(6, 35, 12, 0.72);
            --line: rgba(92, 255, 122, 0.18);
            --green: #9dff9d;
            --green-hot: #59ff87;
            --green-dim: #67c66d;
            --green-faint: rgba(157, 255, 157, 0.66);
            --shadow: rgba(89, 255, 135, 0.22);
          }

          * { box-sizing: border-box; }

          html {
            min-height: 100%;
            background:
              radial-gradient(circle at top, rgba(26, 85, 33, 0.22), transparent 34%),
              radial-gradient(circle at bottom, rgba(13, 60, 20, 0.18), transparent 42%),
              var(--bg);
          }

          body {
            margin: 0;
            min-height: 100vh;
            color: var(--green);
            font: 16px/1.55 "IBM Plex Mono", "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
            text-shadow: 0 0 8px rgba(89, 255, 135, 0.26);
            background: transparent;
            overflow-x: hidden;
          }

          body::before,
          body::after {
            content: "";
            position: fixed;
            inset: 0;
            pointer-events: none;
            z-index: 0;
          }

          body::before {
            background: repeating-linear-gradient(
              to bottom,
              rgba(255, 255, 255, 0.025),
              rgba(255, 255, 255, 0.025) 1px,
              transparent 1px,
              transparent 3px
            );
            opacity: 0.26;
            mix-blend-mode: screen;
          }

          body::after {
            background:
              radial-gradient(circle at center, transparent 52%, rgba(0, 0, 0, 0.45) 100%),
              linear-gradient(to bottom, rgba(0, 0, 0, 0.08), rgba(89, 255, 135, 0.03), rgba(0, 0, 0, 0.18));
            animation: flicker 0.16s infinite alternate;
          }

          .shell {
            position: relative;
            z-index: 1;
            width: min(1100px, calc(100% - 32px));
            margin: 28px auto;
            padding: 18px;
            border: 1px solid var(--line);
            border-radius: 18px;
            background: linear-gradient(180deg, rgba(6, 20, 9, 0.96), rgba(3, 12, 6, 0.94));
            box-shadow:
              0 0 0 1px rgba(89, 255, 135, 0.05) inset,
              0 0 24px var(--shadow),
              0 0 80px rgba(0, 0, 0, 0.45);
          }

          .shell-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            margin-bottom: 18px;
            padding-bottom: 14px;
            border-bottom: 1px solid var(--line);
            color: var(--green-faint);
            font-size: 0.92rem;
          }

          .window-dots {
            display: inline-flex;
            gap: 8px;
            align-items: center;
          }

          .window-dots span {
            width: 10px;
            height: 10px;
            border-radius: 999px;
            border: 1px solid rgba(157, 255, 157, 0.4);
            background: rgba(157, 255, 157, 0.12);
            box-shadow: 0 0 10px rgba(89, 255, 135, 0.12);
          }

          .badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            border: 1px solid rgba(89, 255, 135, 0.35);
            border-radius: 999px;
            padding: 6px 12px;
            color: var(--green-hot);
            background: rgba(8, 30, 12, 0.8);
            box-shadow: 0 0 16px rgba(89, 255, 135, 0.12) inset;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            font-size: 0.78rem;
          }

          .badge::before {
            content: "";
            width: 8px;
            height: 8px;
            border-radius: 999px;
            background: var(--green-hot);
            box-shadow: 0 0 10px var(--green-hot);
            animation: pulse 1.4s infinite ease-in-out;
          }

          .prompt,
          .headline,
          .command {
            color: var(--green-faint);
          }

          .command {
            margin-bottom: 10px;
          }

          .hero {
            margin-bottom: 20px;
          }

          h1 {
            margin: 0;
            font-size: clamp(2rem, 5vw, 4rem);
            line-height: 1;
            letter-spacing: 0.04em;
            text-transform: lowercase;
          }

          .cursor {
            display: inline-block;
            width: 0.72ch;
            height: 1em;
            margin-left: 0.16ch;
            vertical-align: -0.12em;
            background: currentColor;
            box-shadow: 0 0 10px currentColor;
            animation: blink 1s step-end infinite;
          }

          .subhead {
            margin: 10px 0 0;
            max-width: 70ch;
            color: var(--green-faint);
          }

          .ticker {
            margin: 16px 0 24px;
            padding: 10px 12px;
            border: 1px solid var(--line);
            border-radius: 12px;
            background: var(--panel-soft);
            color: var(--green-hot);
            overflow: hidden;
            white-space: nowrap;
          }

          .ticker span {
            display: inline-block;
            padding-left: 100%;
            animation: marquee 18s linear infinite;
          }

          .grid {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 16px;
          }

          .panel {
            padding: 18px;
            border: 1px solid var(--line);
            border-radius: 16px;
            background: linear-gradient(180deg, rgba(6, 27, 10, 0.92), rgba(4, 17, 7, 0.86));
            box-shadow: 0 0 0 1px rgba(89, 255, 135, 0.04) inset;
          }

          .label {
            margin-bottom: 10px;
            color: var(--green-faint);
            text-transform: uppercase;
            letter-spacing: 0.08em;
            font-size: 0.78rem;
          }

          .value {
            font-size: clamp(1.6rem, 4vw, 2.4rem);
            line-height: 1.1;
            color: var(--green-hot);
          }

          .meta {
            margin-top: 8px;
            color: var(--green-faint);
            font-size: 0.92rem;
          }

          .meter {
            margin-top: 14px;
            height: 10px;
            border-radius: 999px;
            border: 1px solid rgba(89, 255, 135, 0.16);
            background: rgba(0, 0, 0, 0.28);
            overflow: hidden;
          }

          .meter > span {
            display: block;
            height: 100%;
            width: var(--fill);
            min-width: 2%;
            background: linear-gradient(90deg, rgba(62, 192, 88, 0.7), rgba(89, 255, 135, 0.98));
            box-shadow: 0 0 18px rgba(89, 255, 135, 0.45);
          }

          .details {
            display: grid;
            grid-template-columns: 1.3fr 0.7fr;
            gap: 16px;
            margin-top: 16px;
          }

          dl {
            margin: 0;
            display: grid;
            grid-template-columns: max-content 1fr;
            gap: 10px 14px;
          }

          dt {
            color: var(--green-faint);
          }

          dd {
            margin: 0;
          }

          code,
          a {
            color: var(--green-hot);
          }

          a {
            text-decoration: none;
            border-bottom: 1px dotted rgba(89, 255, 135, 0.35);
          }

          a:hover {
            border-bottom-style: solid;
          }

          .links {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-top: 12px;
          }

          .links a {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 10px;
            border: 1px solid var(--line);
            border-radius: 10px;
            background: rgba(8, 28, 12, 0.7);
          }

          .footer {
            margin-top: 18px;
            color: rgba(157, 255, 157, 0.58);
            font-size: 0.84rem;
          }

          @keyframes blink {
            0%, 49% { opacity: 1; }
            50%, 100% { opacity: 0; }
          }

          @keyframes flicker {
            from { opacity: 0.14; }
            to { opacity: 0.22; }
          }

          @keyframes pulse {
            0%, 100% { opacity: 0.75; transform: scale(0.95); }
            50% { opacity: 1; transform: scale(1.08); }
          }

          @keyframes marquee {
            from { transform: translateX(0); }
            to { transform: translateX(-100%); }
          }

          @media (max-width: 800px) {
            .grid,
            .details {
              grid-template-columns: 1fr;
            }

            .shell {
              width: min(100% - 20px, 1100px);
              margin: 10px auto;
              padding: 14px;
            }

            .shell-header {
              flex-direction: column;
              align-items: flex-start;
            }
          }
        </style>
      </head>
      <body>
        <main class="shell">
          <div class="shell-header">
            <div>
              <div class="window-dots" aria-hidden="true"><span></span><span></span><span></span></div>
              <span class="prompt"> guest@#{h(stats[:hostname])}:~$ ./banoffee-board --public</span>
            </div>
            <div class="badge">#{h(stats[:health])}</div>
          </div>

          <div class="command">[#{h(now.strftime("%Y-%m-%d %H:%M:%S UTC"))}] telemetry snapshot initialized</div>

          <section class="hero">
            <h1>banoffee-board<span class="cursor" aria-hidden="true"></span></h1>
          </section>

          <div class="ticker"><span>#{h(headline)} :: host uptime #{h(format_duration(uptime[:host_seconds]))} :: app uptime #{h(format_duration(uptime[:app_seconds]))} :: refresh interval #{REFRESH_SECONDS}s</span></div>

          <section class="grid" aria-label="System metrics">
            <article class="panel">
              <div class="label">Average load</div>
              <div class="value">#{h(load_summary)}</div>
              <div class="meta">1m / 5m / 15m across #{h(load[:cores])} cores · pressure #{h(load[:pressure_percent])}% · mood #{h(load[:mood])}</div>
              <div class="meter" style="--fill: #{[[load[:pressure_percent], 4].max, 100].min}%"><span></span></div>
            </article>

            <article class="panel">
              <div class="label">Memory</div>
              <div class="value">#{h(memory[:used_percent])}% used</div>
              <div class="meta">#{h(format_bytes(memory[:used]))} used · #{h(format_bytes(memory[:available]))} available · #{h(format_bytes(memory[:total]))} total</div>
              <div class="meter" style="--fill: #{[[memory[:used_percent], 2].max, 100].min}%"><span></span></div>
            </article>

            <article class="panel">
              <div class="label">Disk</div>
              <div class="value">#{h(disk[:used_percent])}% used</div>
              <div class="meta">#{h(format_bytes(disk[:used]))} used · #{h(format_bytes(disk[:available]))} free · #{h(format_bytes(disk[:total]))} on #{h(disk[:path])}</div>
              <div class="meter" style="--fill: #{[[disk[:used_percent], 2].max, 100].min}%"><span></span></div>
            </article>

            <article class="panel">
              <div class="label">Uptime</div>
              <div class="value">#{h(format_duration(uptime[:host_seconds]))}</div>
              <div class="meta">host kernel uptime · app process alive for #{h(format_duration(uptime[:app_seconds]))}</div>
              <div class="meter" style="--fill: #{[[uptime[:app_seconds] / 864.0, 2].max, 100].min}%"><span></span></div>
            </article>
          </section>

          <section class="details">
            <article class="panel">
              <div class="label">Signal details</div>
              <dl>
                <dt>health</dt>
                <dd>#{h(stats[:health])}</dd>
                <dt>hostname</dt>
                <dd><code>#{h(stats[:hostname])}</code></dd>
                <dt>updated</dt>
                <dd>#{h(now.strftime("%Y-%m-%d %H:%M:%S UTC"))}</dd>
                <dt>version</dt>
                <dd><code>#{h(stats[:version])}</code></dd>
                <dt>refresh</dt>
                <dd>automatic every #{REFRESH_SECONDS} seconds</dd>
              </dl>
            </article>

            <article class="panel">
              <div class="label">Links</div>
              <div class="links">
                <a href="/up">/up</a>
                <a href="/status.json">/status.json</a>
                <a href="#{h(stats[:repo_url])}">repo</a>
              </div>
            </article>
          </section>

        </main>
      </body>
    </html>
  HTML
end

app = proc do |env|
  req = Rack::Request.new(env)
  stats = collect_stats

  case req.path
  when "/up"
    [200, { "content-type" => "text/plain; charset=utf-8" }, ["OK\n"]]
  when "/status.json"
    payload = {
      status: stats[:health].downcase,
      refreshed_at: stats[:now].iso8601,
      hostname: stats[:hostname],
      version: stats[:version],
      load: stats[:load],
      memory: stats[:memory],
      disk: stats[:disk],
      uptime: stats[:uptime]
    }

    [200, { "content-type" => "application/json; charset=utf-8" }, [JSON.pretty_generate(payload)]]
  when "/"
    [200, { "content-type" => "text/html; charset=utf-8" }, [page(stats)]]
  else
    [404, { "content-type" => "text/plain; charset=utf-8" }, ["Not found\n"]]
  end
end

run app
