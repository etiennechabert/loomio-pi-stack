#!/usr/bin/env ruby
# Show Sidekiq queue status, dead jobs, and retry jobs

require 'sidekiq/api'

stats = Sidekiq::Stats.new
puts "\n\033[0;36mOverall Stats:\033[0m"
puts "  Processed: #{stats.processed}"
puts "  Failed: #{stats.failed}"
puts "  Enqueued: #{stats.enqueued}"
puts "  Scheduled: #{stats.scheduled_size}"
puts "  Retries: #{stats.retry_size}"
puts "  Dead: #{stats.dead_size}"
puts "  Workers: #{stats.workers_size}"

puts "\n\033[0;36mQueues:\033[0m"
Sidekiq::Queue.all.each do |queue|
  color = queue.size > 0 ? "\033[1;33m" : "\033[0;32m"
  puts "  #{color}#{queue.name.ljust(20)}\033[0m Size: #{queue.size.to_s.rjust(4)} | Latency: #{queue.latency.round(2)}s"
end

dead_set = Sidekiq::DeadSet.new
if dead_set.size > 0
  puts "\n\033[0;31mDead Jobs (#{dead_set.size}):\033[0m"
  dead_set.first(10).each_with_index do |job, i|
    puts "  #{i+1}. [#{job.klass}] Failed at: #{job.failed_at}"
    puts "     Error: #{job['error_class']}: #{job['error_message']}"
    puts "     Args: #{job.args.inspect[0..80]}..." if job.args
    puts ""
  end
  puts "  \033[0;33m(Showing first 10 of #{dead_set.size} dead jobs)\033[0m" if dead_set.size > 10
else
  puts "\n\033[0;32m✓ No dead jobs\033[0m"
end

retry_set = Sidekiq::RetrySet.new
if retry_set.size > 0
  puts "\n\033[0;33mRetrying Jobs (#{retry_set.size}):\033[0m"
  retry_set.first(5).each_with_index do |job, i|
    puts "  #{i+1}. [#{job.klass}] Retry: #{job['retry_count']}/#{job['retry']} | Next: #{Time.at(job.at).strftime('%H:%M:%S')}"
    puts "     Error: #{job['error_class']}: #{job['error_message']}"
    puts ""
  end
  puts "  \033[0;33m(Showing first 5 of #{retry_set.size} retrying jobs)\033[0m" if retry_set.size > 5
end
