# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/plain"
require "logstash/event"
require "insist"
require 'logstash/plugin_mixins/ecs_compatibility_support/spec_helper'

describe LogStash::Codecs::Plain, :ecs_compatibility_support do
  context "#decode" do

    ecs_compatibility_matrix(:disabled, :v1, :v8 => :v1) do |ecs_select|

      before(:each) do
        allow_any_instance_of(described_class).to receive(:ecs_compatibility).and_return(ecs_compatibility)
      end

      let(:message) { "Testing decoding." }

      it "should return a valid event" do
        count = 0
        subject.decode(message) do |event|
          count += 1
          expect( event ).to be_a LogStash::Event
        end
        expect( count ).to eql 1
      end

      it "sets event.original in ECS mode" do
        subject.decode(message) do |event|
          expect( event.get("[event][original]") ).to eql message
        end
      end if ecs_select.active_mode != :disabled

    end

    context "using default UTF-8 charset" do

      it "should decode valid UTF-8 input" do
        ["foobar", "κόσμε"].each do |data|
          insist { data.encoding.name } == "UTF-8"
          insist { data.valid_encoding? } == true
          subject.decode(data) do |event|
            insist { event.get("message") } == data
            insist { event.get("message").encoding.name } == "UTF-8"
          end
        end
      end

      it "should escape invalid sequences" do
        ["foo \xED\xB9\x81\xC3", "bar \xAD"].each do |data|
          insist { data.encoding.name } == "UTF-8"
          insist { data.valid_encoding? } == false
          subject.decode(data) do |event|
            insist { event.get("message") } == data.inspect[1..-2]
            insist { event.get("message").encoding.name } == "UTF-8"
          end
        end
      end
    end


    context "with valid non UTF-8 source encoding" do

      subject{LogStash::Codecs::Plain.new("charset" => "ISO-8859-1")}

      it "should encode to UTF-8" do
        samples = [
          ["foobar", "foobar"],
          ["\xE0 Montr\xE9al", "à Montréal"],
        ]
        samples.map{|(a, b)| [a.force_encoding("ISO-8859-1"), b]}.each do |(a, b)|
          insist { a.encoding.name } == "ISO-8859-1"
          insist { b.encoding.name } == "UTF-8"
          insist { a.valid_encoding? } == true

          subject.decode(a) do |event|
            insist { event.get("message") } == b
            insist { event.get("message").encoding.name } == "UTF-8"
          end
        end
      end
    end

    context "with invalid non UTF-8 source encoding" do

      subject{LogStash::Codecs::Plain.new("charset" => "ASCII-8BIT")}

      it "should encode to UTF-8" do
        samples = [
          ["\xE0 Montr\xE9al", "� Montr�al"],
          ["\xCE\xBA\xCF\x8C\xCF\x83\xCE\xBC\xCE\xB5", "����������"],
        ]
        samples.map{|(a, b)| [a.force_encoding("ASCII-8BIT"), b]}.each do |(a, b)|
          insist { a.encoding.name } == "ASCII-8BIT"
          insist { b.encoding.name } == "UTF-8"
          insist { a.valid_encoding? } == true

          subject.decode(a) do |event|
            insist { event.get("message") } == b
            insist { event.get("message").encoding.name } == "UTF-8"
          end
        end
      end
    end
  end

  context "#encode" do
    it "should return a plain text encoding" do
      event = LogStash::Event.new
      event.set("message", "Hello World.")
      subject.on_event do |event, data|
        insist { data } == event.to_s
      end
      subject.encode(event)
    end

    it "should respect the format setting" do
      format = "%{[hello]} %{[something][fancy]}"
      codec = LogStash::Codecs::Plain.new("format" => format)
      event = LogStash::Event.new("hello" => "world", "something" => { "fancy" => 123 })
      codec.on_event do |event, data|
        insist { data } == event.sprintf(format)
      end
      codec.encode(event)
    end
  end
end
