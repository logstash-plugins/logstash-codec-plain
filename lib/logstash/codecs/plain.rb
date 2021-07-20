# encoding: utf-8
require "logstash/codecs/base"
require "logstash/util/charset"

require 'logstash/plugin_mixins/ecs_compatibility_support'
require 'logstash/plugin_mixins/event_support/event_factory_adapter'

# The "plain" codec is for plain text with no delimiting between events.
#
# This is mainly useful on inputs and outputs that already have a defined
# framing in their transport protocol (such as zeromq, rabbitmq, redis, etc)
class LogStash::Codecs::Plain < LogStash::Codecs::Base

  include LogStash::PluginMixins::ECSCompatibilitySupport(:disabled, :v1, :v8 => :v1)
  include LogStash::PluginMixins::EventSupport::EventFactoryAdapter

  config_name "plain"

  # Set the message you which to emit for each event. This supports `sprintf`
  # strings.
  #
  # This setting only affects outputs (encoding of events).
  config :format, :validate => :string

  # The character encoding used in this input. Examples include `UTF-8`
  # and `cp1252`
  #
  # This setting is useful if your log files are in `Latin-1` (aka `cp1252`)
  # or in another character set other than `UTF-8`.
  #
  # This only affects "plain" format logs since json is `UTF-8` already.
  config :charset, :validate => ::Encoding.name_list, :default => "UTF-8"

  def initialize(*params)
    super

    @original_field = ecs_select[disabled: nil, v1: '[event][original]']

    @converter = LogStash::Util::Charset.new(@charset)
    @converter.logger = @logger
  end

  def register
    # no-op
  end

  MESSAGE_FIELD = "message".freeze

  def decode(data)
    message = @converter.convert(data)
    event = event_factory.new_event
    event.set MESSAGE_FIELD, message
    event.set @original_field, message.dup.freeze if @original_field
    yield event
  end

  def encode(event)
    encoded = @format ? event.sprintf(@format) : event.to_s
    @on_event.call(event, encoded)
  end
end
