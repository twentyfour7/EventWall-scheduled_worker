FROM shannywu/ruby-http:2.3.1

WORKDIR /worker

ADD Gemfile .
ADD Gemfile.lock .
RUN apk add --update libxml2-dev libxslt-dev
RUN bundle config build.nokogiri --use-system-libraries
RUN bundle install

ADD update_worker.rb .

ENTRYPOINT ruby update_worker.rb

# build image with:
#   docker build --rm --force-rm -t shannywu/eventwall_update:0.2.0 .

# push to docker hub with:
#   docker push shannywu/eventwall_update:0.2.0
