FROM ruby:3.3-slim

WORKDIR /app

RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile ./
RUN bundle install

COPY config.ru ./

EXPOSE 9292

CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:9292", "config.ru"]
