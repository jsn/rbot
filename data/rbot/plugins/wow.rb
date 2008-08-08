#-- vim:sw=2:et
#++
#
# :title: World of Warcraft Realm Status plugin for rbot
#
# Author:: MrChucho (mrchucho@mrchucho.net)
# Copyright:: (C) 2006 Ralph M. Churchill
#
# Requires:: insatiable appetite for World of Warcraft

require 'rexml/document'

class Realm
    attr_accessor :name,:status,:type,:pop
    def initialize(name,status,type,pop)
        self.name = pretty_realm(name)
        self.status = pretty_status(status)
        self.type = pretty_type(type)
        self.pop = pretty_pop(pop)
    end
    def to_s
        "#{name} (#{type}) Status: #{status} Population: #{pop}"
    end
    # just a longer, tabluar format
    # might be good if displaying multiple realms
    def _to_s
        sprintf("%-8s %-20s %-8s %-9s\n%-11s %-22s %-8s %-9s",
            "Status","Realm","Type","Population",
            status,name,type,pop)
    end
private
    def pretty_status(status)
        case status
        when 1
            "3Up"
        when 2
            "5Down"
        end
    end
    def pretty_pop(pop)
        case pop
        when 1
            "3Low"
        when 2
            "7Medium"
        when 3
            "4High"
        when 4
            "5Max(Queued)"
        end
    end
    def pretty_realm(realm)
        "#{realm}"
    end
    def pretty_type(type)
        case type
        when 0
            'RP-PVP'
        when 1
            'Normal'
        when 2
            'PVP'
        when 3
            'RP'
        end
    end
end

class RealmPlugin < Plugin
    USAGE="realm <realm> => determine the status of a Warcraft realm"
    def initialize
        super
        class << @registry
            def store(val)
                val
            end
            def restore(val)
                val
            end
        end
    end
    def help(plugin,topic="")
        USAGE
    end
    def usage(m,params={})
        m.reply USAGE
    end
    def get_realm_status(realm_name)
        begin
          xmldoc = @bot.httputil.get("http://www.worldofwarcraft.com/realmstatus/status.xml", :cache => false)
          raise "unable to retrieve realm status" unless xmldoc
          realm_list = (REXML::Document.new xmldoc).root
          realm_data = realm_list.get_elements("//r[@n=\"#{realm_name}\"]").first
          if realm_data and realm_data.attributes.any? then
            realm = Realm.new(
              realm_data.attributes['n'],
              realm_data.attributes['s'].to_i,
              realm_data.attributes['t'].to_i,
              realm_data.attributes['l'].to_i)
            realm.to_s
          else
            "realm #{realm_name} not found."
          end
        rescue => err
          "error retrieving realm status: #{err}"
        end
    end
    def realm(m,params)
      if params[:realm_name] and params[:realm_name].any?
        realm_name = params[:realm_name].collect{|tok|
          tok.capitalize
        }.join(' ')
        @registry[m.sourcenick] = realm_name
        m.reply get_realm_status(realm_name)
      else
        if @registry.has_key?(m.sourcenick)
          realm_name = @registry[m.sourcenick]
          m.reply get_realm_status(realm_name)
        else
          m.reply "I don't know which realm you want.\n#{USAGE}"
        end
      end
    end
end
plugin = RealmPlugin.new
plugin.map 'realm *realm_name',
  :defaults => {:realm_name => false}, :thread => true
