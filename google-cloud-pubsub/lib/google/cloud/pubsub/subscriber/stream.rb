# Copyright 2017 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "google/cloud/pubsub/subscriber/async_pusher"
require "google/cloud/pubsub/subscriber/enumerator_queue"
require "google/cloud/pubsub/service"
require "google/cloud/errors"
require "monitor"
require "concurrent"

module Google
  module Cloud
    module Pubsub
      class Subscriber
        ##
        # @private
        class Stream
          include MonitorMixin

          ##
          # @private Implementation attributes.
          attr_reader :callback_thread_pool, :push_thread_pool

          ##
          # Subscriber attributes.
          attr_reader :subscriber

          ##
          # @private Create an empty Subscriber::Stream object.
          def initialize subscriber
            @subscriber = subscriber

            @request_queue = nil
            @stopped = nil
            @paused  = nil
            @pause_cond = new_cond

            @inventory = Inventory.new self, subscriber.stream_inventory
            @callback_thread_pool = Concurrent::FixedThreadPool.new \
              subscriber.callback_threads
            @push_thread_pool = Concurrent::FixedThreadPool.new \
              subscriber.push_threads

            super() # to init MonitorMixin
          end

          def start
            synchronize do
              break if @request_queue

              start_streaming!
            end

            self
          end

          def stop
            synchronize do
              break if @stopped

              @stopped = true

              @inventory.stop

              # signal to the background thread that we are unpaused
              @pause_cond.broadcast
            end

            self
          end

          def stopped?
            synchronize { @stopped }
          end

          def paused?
            synchronize { @paused }
          end

          def wait!
            synchronize do
              # Now that the reception thread is dead, make sure all recieved
              # messages have had the callback called.
              @callback_thread_pool.shutdown
              @callback_thread_pool.wait_for_termination

              # Once all the callbacks are complete, we can stop the publisher
              # and send the final request to the steeam.
              if @async_pusher
                request = @async_pusher.stop
                if request
                  Concurrent::Future.new(executor: @push_thread_pool) do
                    @request_queue.push request
                  end.execute
                end
              end

              # Close the push thread pool now that the pusher is closed.
              @push_thread_pool.shutdown
              @push_thread_pool.wait_for_termination

              # Close the stream now that all requests have been made.
              @request_queue.push self unless @request_queue.nil?
            end

            self
          end

          ##
          # @private
          def acknowledge *messages
            ack_ids = coerce_ack_ids messages
            return true if ack_ids.empty?

            synchronize do
              @async_pusher ||= AsyncPusher.new self
              @async_pusher.acknowledge ack_ids
              @inventory.remove ack_ids
              unpause_streaming!
            end

            true
          end

          ##
          # @private
          def delay deadline, *messages
            mod_ack_ids = coerce_ack_ids messages
            return true if mod_ack_ids.empty?

            synchronize do
              @async_pusher ||= AsyncPusher.new self
              @async_pusher.delay deadline, mod_ack_ids
              @inventory.remove mod_ack_ids
              unpause_streaming!
            end

            true
          end

          def async_pusher
            synchronize { @async_pusher }
          end

          def push request
            synchronize { @request_queue.push request }
          end

          def inventory
            synchronize { @inventory }
          end

          ##
          # @private
          def delay_inventory!
            synchronize do
              return true if @inventory.empty?

              @async_pusher ||= AsyncPusher.new self
              @async_pusher.delay subscriber.deadline, @inventory.ack_ids
            end

            true
          end

          # @private
          def to_s
            format "(inventory: %<inv>i, status: %<sts>s)",
                   inv: inventory.count, sts: status
          end

          # @private
          def inspect
            "#<#{self.class.name} #{self}>"
          end

          protected

          # rubocop:disable all

          def background_run enum
            loop do
              synchronize do
                if @paused && !@stopped
                  @pause_cond.wait
                  next
                end
              end

              # Break loop, close thread if stopped
              break if synchronize { @stopped }

              begin
                # Cannot syncronize the enumerator, causes deadlock
                response = enum.next

                # Create a list of all the received ack_id values
                received_ack_ids = response.received_messages.map(&:ack_id)

                synchronize do
                  # Create receipt of received messages reception
                  @async_pusher ||= AsyncPusher.new self
                  @async_pusher.delay subscriber.deadline, received_ack_ids

                  # Add received messages to inventory
                  @inventory.add received_ack_ids
                end

                response.received_messages.each do |rec_msg_grpc|
                  rec_msg = ReceivedMessage.from_grpc(rec_msg_grpc, self)
                  synchronize do
                    # Call user provided code for received message
                    perform_callback_async rec_msg
                  end
                end
                synchronize { pause_streaming! }
              rescue StopIteration
                break
              end
            end
            # Has the loop broken but we aren't stopped?
            synchronize { raise "need to restart thread" unless @stopped }
          rescue GRPC::DeadlineExceeded, GRPC::Unavailable, GRPC::Cancelled,
                 GRPC::ResourceExhausted, GRPC::Internal, GRPC::Core::CallError
            # The GAPIC layer will raise DeadlineExceeded when stream is opened
            # longer than the timeout value it is configured for. When this
            # happends, restart the stream stealthly.
            # Also stealthly restart the stream on Unavailable, Cancelled,
            # ResourceExhausted, and Internal.
            synchronize { start_streaming! }
          rescue StandardError => e
            synchronize do
              if @stopped
                Thread.main.raise Google::Cloud::Error.from_error(e)
              else
                start_streaming!
              end
            end
          end

          # rubocop:enable all

          def perform_callback_async rec_msg
            Concurrent::Future.new(executor: callback_thread_pool) do
              subscriber.callback.call rec_msg
            end.execute
          end

          def start_streaming!
            # Don't allow a stream to restart if already stopped
            return if @stopped

            # signal to the previous queue to shut down
            old_queue = []
            old_queue = @request_queue.quit_and_dump_queue if @request_queue

            @request_queue = EnumeratorQueue.new self
            @request_queue.push initial_input_request
            old_queue.each { |obj| @request_queue.push obj }
            output_enum = subscriber.service.streaming_pull @request_queue.each

            @stopped = nil
            @paused  = nil

            # create new background thread to handle new enumerator
            @background_thread = Thread.new(output_enum) do |enum|
              background_run enum
            end
          end

          def pause_streaming!
            return unless pause_streaming?

            @paused = true
          end

          def pause_streaming?
            return if @stopped
            return if @paused

            @inventory.full?
          end

          def unpause_streaming!
            return unless unpause_streaming?

            @paused = nil
            # signal to the background thread that we are unpaused
            @pause_cond.broadcast
          end

          def unpause_streaming?
            return if @stopped
            return if @paused.nil?

            @inventory.count < @inventory.limit * 0.8
          end

          def initial_input_request
            Google::Pubsub::V1::StreamingPullRequest.new.tap do |req|
              req.subscription = subscriber.subscription_name
              req.stream_ack_deadline_seconds = subscriber.deadline
              req.modify_deadline_ack_ids += @inventory.ack_ids
              req.modify_deadline_seconds += \
                @inventory.ack_ids.map { subscriber.deadline }
            end
          end

          ##
          # Makes sure the values are the `ack_id`. If given several
          # {ReceivedMessage} objects extract the `ack_id` values.
          def coerce_ack_ids messages
            Array(messages).flatten.map do |msg|
              msg.respond_to?(:ack_id) ? msg.ack_id : msg.to_s
            end
          end

          def status
            return "not started" if @background_thread.nil?

            status = @background_thread.status
            return "error" if status.nil?
            return "stopped" if status == false
            status
          end

          ##
          # @private
          class Inventory
            include MonitorMixin

            attr_reader :stream, :limit

            def initialize stream, limit
              @stream = stream
              @limit = limit
              @_ack_ids = []
              @wait_cond = new_cond

              super()
            end

            def ack_ids
              @_ack_ids
            end

            def add *ack_ids
              ack_ids = Array(ack_ids).flatten
              synchronize do
                @_ack_ids += ack_ids
                unless @stopped
                  @background_thread ||= Thread.new { background_run }
                end
              end
            end

            def remove *ack_ids
              ack_ids = Array(ack_ids).flatten
              synchronize do
                @_ack_ids -= ack_ids
                if @_ack_ids.empty?
                  if @background_thread
                    @background_thread.kill
                    @background_thread = nil
                  end
                end
              end
            end

            def count
              synchronize do
                @_ack_ids.count
              end
            end

            def empty?
              synchronize do
                @_ack_ids.empty?
              end
            end

            def stop
              synchronize do
                @stopped = true
                @background_thread.kill if @background_thread
              end
            end

            def full?
              count >= limit
            end

            protected

            def background_run
              until synchronize { @stopped }
                delay = calc_delay
                synchronize { @wait_cond.wait delay }

                stream.delay_inventory!
              end
            end

            def calc_delay
              (stream.subscriber.deadline - 3) * rand(0.8..0.9)
            end
          end
        end
      end
    end
  end
end
