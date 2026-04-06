app = proc do |env|
  req = Rack::Request.new(env)

  case req.path
  when "/up"
    [200, { "content-type" => "text/plain" }, ["OK\n"]]
  when "/"
    hostname = ENV["HOSTNAME"] || `hostname`.strip
    version  = ENV["APP_VERSION"] || "dev"
    repo_url = ENV["REPO_URL"] || "https://github.com"
    now      = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S UTC")

    body = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Banoffee Board</title>
          <style>
            body {
              font-family: system-ui, sans-serif;
              max-width: 720px;
              margin: 40px auto;
              padding: 0 20px;
              line-height: 1.5;
            }
            .card {
              border: 1px solid #ddd;
              border-radius: 12px;
              padding: 20px;
            }
            ul { padding-left: 20px; }
            code {
              background: #f4f4f4;
              padding: 2px 6px;
              border-radius: 6px;
            }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>Banoffee Board</h1>
            <p>oh-my-banoffee-pie is alive</p>

            <h2>Runtime</h2>
            <ul>
              <li><strong>Hostname:</strong> #{hostname}</li>
              <li><strong>Time:</strong> #{now}</li>
              <li><strong>Version:</strong> #{version}</li>
            </ul>

            <h2>Links</h2>
            <ul>
              <li><a href="/up">Health check</a></li>
              <li><a href="#{repo_url}">GitHub repo</a></li>
            </ul>
          </div>
        </body>
      </html>
    HTML

    [200, { "content-type" => "text/html" }, [body]]
  else
    [404, { "content-type" => "text/plain" }, ["Not found\n"]]
  end
end

run app
