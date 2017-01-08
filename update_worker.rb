# frozen_string_literal: true
require 'ostruct'
require 'http'
require 'yaml'
require 'aws-sdk'
require 'kktix_api'

## Scheduled worker regularly runs updates using queued URLs
# e.g.: {"url":"https://localhost:9292/api/v0.1/group/1/update"}
class UpdateWorker
  def initialize(config_file)
    @config = worker_configuration(config_file)
    setup_environment_variables
    @sqs = Aws::SQS::Client.new
  end

  def call
    process_update_orgs
    process_update_nthu
  end

  private

  def worker_configuration(config_file)
    puts "CONFIG_FILE: #{config_file}"
    config = OpenStruct.new YAML.load(File.read(config_file))
    puts "AWS_REGION: #{config.AWS_REGION}"
    config
  end

  def setup_environment_variables
    ENV['AWS_REGION'] = @config.AWS_REGION
    ENV['AWS_ACCESS_KEY_ID'] = @config.AWS_ACCESS_KEY_ID
    ENV['AWS_SECRET_ACCESS_KEY'] = @config.AWS_SECRET_ACCESS_KEY
  end

  def find_queue_url
    @sqs.get_queue_url(queue_name: @config.UPDATE_QUEUE).queue_url
  end

  def process_update_nthu
    categories = %w(art student acdemic)
    categories.each do |category|
      response = HTTP.get("#{@config.KKTIX_EVENT_API}/load/nthu/#{category}")
      raise "API failed: #{update_url}" if response.status >= 400
    end
  end

  def process_update_orgs
    processed = {}

    gather_today_org.map do |slug|
      processed[slug] = send_update_request(slug) unless processed[slug]
    end

    poller = Aws::SQS::QueuePoller.new(find_queue_url)
    poller.poll(wait_time_seconds: nil, idle_timeout: 5) do |msg|
      slug = JSON.parse(msg.body)['slug']
      processed[slug] = send_update_request(slug) unless processed[slug]
    end
  end

  def send_update_request(slug)
    puts "UPDATING: #{slug}"
    response = HTTP.get("#{@config.KKTIX_EVENT_API}/load/kk/#{slug}")
    raise "API failed: #{slug}" if response.status >= 400
    true
  end

  def gather_today_org
    puts 'UPDATING: KKTIX'
    slugs = KktixEvent::KktixApi.events.map { |event| parse_org_slug(event[:url]) }
    slugs
  end

  def parse_org_slug(url)
    match_data = url.match('(\w+)\.kktix\.cc')
    match_data.captures[0].lower
  end
end

# begin
  UpdateWorker.new(ENV['CONFIG_FILE']).call
  puts 'STATUS: SUCCESS'
# rescue => e
#   puts "STATUS: ERROR (#{e.inspect})"
# end
