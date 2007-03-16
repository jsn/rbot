#-- vim:sw=4:et
#++
#
# :title: RemoteCtl plugin
#
# Author:: jsn (dmitry kim) <dmitry dot kim at gmail dot org>
# Copyright:: (C) 2007 dmitry kim
# License:: in public domain
#
# Adds druby remote command execution to rbot. See 'bin/rbot-remote' for
# example usage.

class RemoteCtlPlugin < Plugin
    include RemotePlugin

    def remote_command(m, params)
        s = params[:string].to_s
        new_m = PrivMessage.new(@bot, @bot.server, @bot.server.user('-remote.client-'), @bot.myself, s)
        @bot.plugins.delegate "listen", new_m
        @bot.plugins.privmsg(new_m)
    end
end

me = RemoteCtlPlugin.new

me.remote_map 'dispatch *string',
    :action => 'remote_command',
    :action_path => 'dispatch'

me.default_auth('*', false)
