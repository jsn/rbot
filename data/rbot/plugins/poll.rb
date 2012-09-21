#-- vim:ts=2:et:sw=2
#++
#
# :title: Voting plugin for rbot
# Author:: David Gadling <dave@toasterwaffles.com>
# Copyright:: (C) 2010 David Gadling
# License:: BSD
#
# Submit a poll question to a channel, wait for glorious outcome.
#
# TODO better display for start/end times
# TODO 'until ...' time spec
# TODO early poll termination
# TODO option to inform people about running polls on join (if they haven't voted yet)

class ::Poll
  attr_accessor :id, :author, :channel, :running, :ends_at, :started
  attr_accessor :question, :answers, :duration, :voters, :outcome

  def initialize(originating_message, question, answers, duration)
    @author = originating_message.sourcenick
    @channel = originating_message.channel
    @question = question
    @running = false
    @duration = duration

    @answers = Hash.new
    @voters  = Hash.new

    answer_index = "A"
    answers.each do |ans|
      @answers[answer_index] = {
        :value => ans,
        :count => 0
      }
      answer_index.next!
    end
  end

  def start!
    return if @running

    @started = Time.now
    @ends_at = @started + @duration
    @running = true
  end

  def stop!
    return if @running == false
    @running = false
  end

  def record_vote(voter, choice)
    if @running == false
      return _("poll's closed!")
    end

    if @voters.has_key? voter
      return _("you already voted for %{vote}!") % {
        :vote => @voters[voter]
      }
    end

    choice.upcase!
    if @answers.has_key? choice
      @answers[choice][:count] += 1
      @voters[voter] = choice

      return _("recorded your vote for %{choice}: %{value}") % {
        :choice => choice,
        :value => @answers[choice][:value]
      }
    else
      return _("don't have an option %{choice}") % {
        :choice => choice
      }
    end
  end

  def printing_values
    return Hash[:question => @question,
            :answers => @answers.keys.collect { |a| [a, @answers[a][:value]] }
    ]
  end

  def to_s
    return @question
  end

  def options
    options = _("options are: ").dup
    @answers.each { |letter, info|
      options << "#{Bold}#{letter}#{NormalText}) #{info[:value]} "
    }
    return options
  end
end

class PollPlugin < Plugin
  Config.register Config::IntegerValue.new('poll.max_concurrent_polls',
    :default => 2,
    :desc => _("How many polls a user can have running at once"))
  Config.register Config::StringValue.new('poll.default_duration',
    :default => "2 minutes",
    :desc => _("How long a poll will accept answers, by default."))
  Config.register Config::BooleanValue.new('poll.save_results',
    :default => true,
    :desc => _("Should we save results until we see the nick of the pollster?"))

  def init_reg_entry(sym, default)
    unless @registry.has_key?(sym)
      @registry[sym] = default
    end
  end

  def initialize()
    super
    init_reg_entry :running, Hash.new
    init_reg_entry :archives, Hash.new
    init_reg_entry :last_poll_id, 0
    running = @registry[:running]
    now = Time.now
    running.each do |id, poll|
      duration = poll.ends_at - Time.now
      if duration > 0
        # keep the poll running
        @bot.timer.add_once(duration) { count_votes(poll.id) }
      else
        # the poll expired while the bot was out, end it
        count_votes(poll.id)
      end
    end
  end

  def authors_running_count(victim)
    return @registry[:running].values.collect { |p|
      if p.author == victim
        1
      else
        0
      end
    }.inject(0) { |acc, v| acc + v }
  end

  def start(m, params)
    author = m.sourcenick
    chan = m.channel

    max_concurrent = @bot.config['poll.max_concurrent_polls']
    if authors_running_count(author) == max_concurrent
      m.reply _("Sorry, you're already at the limit (%{limit}) polls") % {
        :limit => max_concurrent
      }
      return
    end

    input_blob = params[:blob].to_s.strip
    quote_character = input_blob[0,1]
    chunks = input_blob.split(/#{quote_character}\s+#{quote_character}/)
    if chunks.length <= 2
      m.reply _("This isn't a dictatorship!")
      return
    end

    # grab the question, removing the leading quote character
    question = chunks[0][1..-1].strip
    question << "?" unless question[-1,1] == "?"
    answers = chunks[1..-1].map { |a| a.strip }

    # if the last answer terminates with a quote character,
    # there is no time specification, so strip the quote character
    # and assume default duration
    if answers.last[-1,1] == quote_character
      answers.last.chomp!(quote_character)
      time_word = :for
      target_duration = @bot.config['poll.default_duration']
    else
      last_quote = answers.last.rindex(quote_character)
      time_spec = answers.last[(last_quote+1)..-1].strip
      answers.last[last_quote..-1] = String.new
      answers.last.strip!
      # now answers.last is really the (cleaned-up) last answer,
      # while time_spec holds the (cleaned-up) time spec, which
      # should start with 'for' or 'until'
      time_word, target_duration = time_spec.split(/\s+/, 2)
      time_word = time_word.strip.intern rescue nil
    end

    case time_word
    when :for
      duration = Utils.parse_time_offset(target_duration) rescue nil
    else
      # TODO "until <some moment in time>"
      duration = nil
    end

    unless duration
      m.reply _("I don't understand the time spec %{timespec}") % {
        :timespec => "'#{time_word} #{target_duration}'"
      }
      return
    end

    poll = Poll.new(m, question, answers, duration)

    m.reply _("new poll from %{author}: %{question}") % {
      :author => author,
      :question => "#{Bold}#{question}#{Bold}"
    }
    m.reply poll.options

    poll.id = @registry[:last_poll_id] + 1
    poll.start!
    command = _("poll vote %{id} <SINGLE-LETTER>") % {
      :id => poll.id
    }
    instructions = _("you have %{duration}, vote with ").dup
    instructions << _("%{priv} or %{public}")
    m.reply instructions % {
      :duration => "#{Bold}#{target_duration}#{Bold}",
      :priv => "#{Bold}/msg #{@bot.nick} #{command}#{Bold}",
      :public => "#{Bold}#{@bot.config['core.address_prefix'].first}#{command}#{Bold}"
    }

    running = @registry[:running]
    running[poll.id] = poll
    @registry[:running] = running
    @bot.timer.add_once(duration) { count_votes(poll.id) }
    @registry[:last_poll_id] = poll.id
  end

  def count_votes(poll_id)
    poll = @registry[:running][poll_id]

    # Hrm, it vanished!
    return if poll == nil
    poll.stop!

    dest = poll.channel ? poll.channel : poll.author

    @bot.say(dest, _("let's find the answer to: %{q}") % {
      :q => "#{Bold}#{poll.question}#{Bold}"
    })

    sorted = poll.answers.sort { |a,b| b[1][:count]<=>a[1][:count] }

    winner_info = sorted.first
    winner_info << sorted.inject(0) { |accum, choice| accum + choice[1][:count] }

    if winner_info[2] == 0
      poll.outcome = _("nobody voted")
    else
      if sorted[0][1][:count] == sorted[1][1][:count]
        poll.outcome = _("no clear winner: ") +
          sorted.select { |a|
            a[1][:count] > 0
          }.collect { |a|
            _("'#{a[1][:value]}' got #{a[1][:count]} vote#{a[1][:count] > 1 ? 's' : ''}")
          }.join(", ")
      else
        winning_pct = "%3.0f%%" % [ 100 * (winner_info[1][:count] / winner_info[2]) ]
        poll.outcome = n_("the winner was choice %{choice}: %{value} with %{count} vote (%{pct})",
                          "the winner was choice %{choice}: %{value} with %{count} votes (%{pct})",
                          winner_info[1][:count]) % {
          :choice => winner_info[0],
          :value => winner_info[1][:value],
          :count => winner_info[1][:count],
          :pct => winning_pct
        }
      end
    end

    @bot.say dest, poll.outcome

    # Now that we're done, move it to the archives
    archives = @registry[:archives]
    archives[poll_id] = poll
    @registry[:archives] = archives

    # ... and take it out of the running list
    running = @registry[:running]
    running.delete(poll_id)
    @registry[:running] = running
  end

  def list(m, params)
    if @registry[:running].keys.length == 0
      m.reply _("no polls running right now")
      return
    end

    @registry[:running].each { |id, p|
      m.reply _("%{author}'s poll \"%{question}\" (id #%{id}) runs until %{end}") % {
        :author => p.author, :question => p.question, :id => p.id, :end => p.ends_at
      }
    }
  end

  def record_vote(m, params)
    poll_id = params[:id].to_i
    if @registry[:running].has_key?(poll_id) == false
      m.reply _("I don't have poll ##{poll_id} running :(")
      return
    end

    running = @registry[:running]

    poll = running[poll_id]
    result = poll.record_vote(m.sourcenick, params[:choice])

    running[poll_id] = poll
    @registry[:running] = running
    m.reply result
  end

  def info(m, params)
    params[:id] = params[:id].to_i
    if @registry[:running].has_key? params[:id]
      poll = @registry[:running][params[:id]]
    elsif @registry[:archives].has_key? params[:id]
      poll = @registry[:archives][params[:id]]
    else
      m.reply _("sorry, couldn't find poll %{b}#%{id}%{b}") % {
        :bold => Bold,
        :id => params[:id]
      }
      return
    end

    to_reply = _("poll #%{id} was asked by %{bold}%{author}%{bold} in %{bold}%{channel}%{bold} %{started}.").dup
    options = ''
    outcome = ''
    if poll.running
      to_reply << _(" It's still running!")
      if poll.voters.has_key? m.sourcenick
        to_reply << _(" Be patient, it'll end %{end}")
      else
        to_reply << _(" You have until %{end} to vote if you haven't!")
        options << " #{poll.options}"
      end
    else
      outcome << " #{poll.outcome}"
    end

    m.reply((to_reply % {
      :bold => Bold,
      :id => poll.id, :author => poll.author,
      :channel => (poll.channel ? poll.channel : _("private")),
      :started => poll.started,
      :end => poll.ends_at
    }) + options + outcome)
  end

  def help(plugin,topic="")
    case topic
    when "start"
      _("poll [start] 'my question' 'answer1' 'answer2' ['answer3' ...] " +
        "[for 5 minutes] : Start a poll for the given duration. " +
        "If you don't specify a duration the default will be used.")
    when "list"
      _("poll list : Give some info about currently active polls")
    when "info"
      _("poll info #{Bold}id#{Bold} : Get info about /results from a given poll")
    when "vote"
      _("poll vote #{Bold}id choice#{Bold} : Vote on the given poll with your choice")
    else
      _("Hold informative polls: poll start|list|info|vote")
    end
  end
end

plugin = PollPlugin.new
plugin.map 'poll list', :action => 'list'
plugin.map 'poll info :id', :action => 'info'
plugin.map 'poll vote :id :choice', :action => 'record_vote', :threaded => true
plugin.map 'poll [start] *blob', :action => 'start'
