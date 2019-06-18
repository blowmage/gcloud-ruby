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


require "google/cloud/pubsub/subscriber/enumerator_queue"
require "google/cloud/pubsub/subscriber/inventory"
require "google/cloud/pubsub/service"
require "google/cloud/errors"
require "monitor"
require "concurrent"

module Google
  module Cloud
    module PubSub
      class Subscriber
        ##
        # @private
        class Stream
          include MonitorMixin

          ##
          # @private Implementation attributes.
          attr_reader :callback_thread_pool

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

            @inventory = Inventory.new self, @subscriber.stream_inventory
            @callback_thread_pool = Concurrent::CachedThreadPool.new \
              max_threads: @subscriber.callback_threads

            @stream_keepalive_task = Concurrent::TimerTask.new(
              execution_interval: 30
            ) do
              # push empty request every 30 seconds to keep stream alive
              unless inventory.empty?
                push Google::Cloud::PubSub::V1::StreamingPullRequest.new
              end
            end.execute

            super() # to init MonitorMixin
          end

          def start
            synchronize do
              break if @background_thread

              @inventory.start

              start_streaming!
            end

            self
          end

          def stop
            synchronize do
              break if @stopped

              # Close the stream by pushing the sentinel value.
              # The unary pusher does not use the stream, so it can close here.
              @request_queue.push self unless @request_queue.nil?

              # Signal to the background thread that we are stopped.
              @stopped = true
              @pause_cond.broadcast

              # Now that the reception thread is stopped, immediately stop the
              # callback thread pool and purge all pending callbacks.
              @callback_thread_pool.kill

              # Once all the callbacks are stopped, we can stop the inventory.
              @inventory.stop
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
            self
          end

          ##
          # @private
          def acknowledge *messages
            ack_ids = coerce_ack_ids messages
            return true if ack_ids.empty?

            synchronize do
              @inventory.remove ack_ids
              @subscriber.buffer.acknowledge ack_ids
              unpause_streaming!
            end

            true
          end

          ##
          # @private
          def modify_ack_deadline deadline, *messages
            mod_ack_ids = coerce_ack_ids messages
            return true if mod_ack_ids.empty?

            synchronize do
              @inventory.remove mod_ack_ids
              @subscriber.buffer.modify_ack_deadline deadline, mod_ack_ids
              unpause_streaming!
            end

            true
          end

          def push request
            synchronize { @request_queue.push request }
          end

          def inventory
            synchronize { @inventory }
          end

          ##
          # @private
          def renew_lease!
            synchronize do
              return true if @inventory.empty?

              @subscriber.buffer.renew_lease @subscriber.deadline,
                                             @inventory.ack_ids
              unpause_streaming!
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

          # @private
          class RestartStream < StandardError; end

          # rubocop:disable all

          def background_run
            synchronize do
              # Don't allow a stream to restart if already stopped
              return if @stopped

              @stopped = false
              @paused  = false

              # signal to the previous queue to shut down
              old_queue = []
              old_queue = @request_queue.quit_and_dump_queue if @request_queue

              # Always create a new request queue
              @request_queue = EnumeratorQueue.new self
              @request_queue.push initial_input_request
              old_queue.each { |obj| @request_queue.push obj }
            end

            # Call the StreamingPull API to get the response enumerator
            enum = @subscriber.service.streaming_pull @request_queue.each

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
                  @subscriber.buffer.modify_ack_deadline @subscriber.deadline,
                                                         received_ack_ids

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
            # Could be GRPC has thrown an internal error, so restart.
            raise RestartStream unless synchronize { @stopped }

            # We must be stopped, tell the stream to quit.
            stop
          rescue GRPC::Cancelled, GRPC::DeadlineExceeded, GRPC::Internal,
                 GRPC::ResourceExhausted, GRPC::Unauthenticated,
                 GRPC::Unavailable, GRPC::Core::CallError
            # Restart the stream with an incremental back for a retriable error.
            # Also when GRPC raises the internal CallError.

            retry
          rescue RestartStream
            retry
          rescue StandardError => e
            @subscriber.error! e

            retry
          end

          # rubocop:enable all

          def perform_callback_async rec_msg
            return unless callback_thread_pool.running?

            Concurrent::Promises.future_on(
              callback_thread_pool, @subscriber, @inventory, rec_msg
            ) do |sub, inv, msg|
              begin
                sub.callback.call msg
              rescue StandardError => callback_error
                sub.error! callback_error
              ensure
                inv.remove msg.ack_id
              end
            end
          end

          def start_streaming!
            # A Stream will only ever have one background thread. If the thread
            # dies because it was stopped, or because of an unhandled error that
            # could not be recovered from, so be it.
            return if @background_thread

            # create new background thread to handle new enumerator
            back_thread = Thread.new { background_run }

            # create another thread to monitor the background thread
            Thread.new Thread.main, back_thread do |sub_thd, back_thd|
              begin
                back_thd.join

                # Restart unless the stream was previously stoppped
                synchronize do
                  @background_thread = nil
                  start_streaming! unless @stopped
                end
              rescue StandardError => error
                # The stream had an error, so re-raise on the subscriber thread.
                sub_thd.raise error
              end
            end

            # put the streaming thread in an ivar, so we know it is
            @background_thread = back_thread
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
            Google::Cloud::PubSub::V1::StreamingPullRequest.new.tap do |req|
              req.subscription = @subscriber.subscription_name
              req.stream_ack_deadline_seconds = @subscriber.deadline
              req.modify_deadline_ack_ids += @inventory.ack_ids
              req.modify_deadline_seconds += \
                @inventory.ack_ids.map { @subscriber.deadline }
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
        end
      end
    end

    Pubsub = PubSub unless const_defined? :Pubsub
  end
end
