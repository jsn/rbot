#-- vim:sw=2:et
#++
#
# :title: RFC 2821 Client Protocol module
#
# This module defines the Irc::Client class, a class that can handle and
# dispatch messages based on RFC 2821 (Internet Relay Chat: Client Protocol)

module Irc
  # - The server sends Replies 001 to 004 to a user upon
  #   successful registration.

  # "Welcome to the Internet Relay Network
  # <nick>!<user>@<host>"
  #
  RPL_WELCOME=001

  # "Your host is <servername>, running version <ver>"
  RPL_YOURHOST=002

  # "This server was created <date>"
  RPL_CREATED=003

  # "<servername> <version> <available user modes> <available channel modes>"
  RPL_MYINFO=004

  # "005 nick PREFIX=(ov)@+ CHANTYPES=#& :are supported by this server"
  #
  # defines the capabilities supported by the server.
  #
  # Previous RFCs defined message 005 as follows:
  #
  # - Sent by the server to a user to suggest an alternative
  #   server.  This is often used when the connection is
  #   refused because the server is already full.
  #
  # # "Try server <server name>, port <port number>"
  #
  # RPL_BOUNCE=005
  #
  RPL_ISUPPORT=005

  # ":*1<reply> *( " " <reply> )"
  #
  # - Reply format used by USERHOST to list replies to
  #   the query list.  The reply string is composed as
  #   follows:
  #
  # reply = nickname [ "*" ] "=" ( "+" / "-" ) hostname
  #
  # The '*' indicates whether the client has registered
  # as an Operator.  The '-' or '+' characters represent
  # whether the client has set an AWAY message or not
  # respectively.
  #
  RPL_USERHOST=302

  # ":*1<nick> *( " " <nick> )"
  #
  # - Reply format used by ISON to list replies to the
  #   query list.
  #
  RPL_ISON=303

  # - These replies are used with the AWAY command (if
  #   allowed).  RPL_AWAY is sent to any client sending a
  #   PRIVMSG to a client which is away.  RPL_AWAY is only
  #   sent by the server to which the client is connected.
  #   Replies RPL_UNAWAY and RPL_NOWAWAY are sent when the
  #   client removes and sets an AWAY message.

  # "<nick> :<away message>"
  RPL_AWAY=301

  # ":You are no longer marked as being away"
  RPL_UNAWAY=305

  # ":You have been marked as being away"
  RPL_NOWAWAY=306

  # - Replies 311 - 313, 317 - 319 are all replies
  #   generated in response to a WHOIS message.  Given that
  #   there are enough parameters present, the answering
  #   server MUST either formulate a reply out of the above
  #   numerics (if the query nick is found) or return an
  #   error reply.  The '*' in RPL_WHOISUSER is there as
  #   the literal character and not as a wild card.  For
  #   each reply set, only RPL_WHOISCHANNELS may appear
  #   more than once (for long lists of channel names).
  #   The '@' and '+' characters next to the channel name
  #   indicate whether a client is a channel operator or
  #   has been granted permission to speak on a moderated
  #   channel.  The RPL_ENDOFWHOIS reply is used to mark
  #   the end of processing a WHOIS message.

  # "<nick> <user> <host> * :<real name>"
  RPL_WHOISUSER=311

  # "<nick> <server> :<server info>"
  RPL_WHOISSERVER=312

  # "<nick> :is an IRC operator"
  RPL_WHOISOPERATOR=313

  # "<nick> <integer> :seconds idle"
  RPL_WHOISIDLE=317

  # "<nick> :End of WHOIS list"
  RPL_ENDOFWHOIS=318

  # "<nick> :*( ( "@" / "+" ) <channel> " " )"
  RPL_WHOISCHANNELS=319

  # - When replying to a WHOWAS message, a server MUST use
  #   the replies RPL_WHOWASUSER, RPL_WHOISSERVER or
  #   ERR_WASNOSUCHNICK for each nickname in the presented
  #   list.  At the end of all reply batches, there MUST
  #   be RPL_ENDOFWHOWAS (even if there was only one reply
  #   and it was an error).

  # "<nick> <user> <host> * :<real name>"
  RPL_WHOWASUSER=314

  # "<nick> :End of WHOWAS"
  RPL_ENDOFWHOWAS=369

  # - Replies RPL_LIST, RPL_LISTEND mark the actual replies
  #   with data and end of the server's response to a LIST
  #   command.  If there are no channels available to return,
  #   only the end reply MUST be sent.

  # Obsolete. Not used.
  RPL_LISTSTART=321

  # "<channel> <# visible> :<topic>"
  RPL_LIST=322

  # ":End of LIST"
  RPL_LISTEND=323

  # "<channel> <nickname>"
  RPL_UNIQOPIS=325

  # "<channel> <mode> <mode params>"
  RPL_CHANNELMODEIS=324

  # "<channel> <unixtime>"
  RPL_CREATIONTIME=329

  # "<channel> <url>"
  RPL_CHANNEL_URL=328

  # "<channel> :No topic is set"
  RPL_NOTOPIC=331

  # - When sending a TOPIC message to determine the
  #   channel topic, one of two replies is sent.  If
  #   the topic is set, RPL_TOPIC is sent back else
  #   RPL_NOTOPIC.

  # "<channel> :<topic>"
  RPL_TOPIC=332

  # <channel> <set by> <unixtime>
  RPL_TOPIC_INFO=333

  # "<channel> <nick>"
  #
  # - Returned by the server to indicate that the
  #   attempted INVITE message was successful and is
  #   being passed onto the end client.
  #
  RPL_INVITING=341

  # "<user> :Summoning user to IRC"
  #
  # - Returned by a server answering a SUMMON message to
  #   indicate that it is summoning that user.
  #
  RPL_SUMMONING=342

  # "<channel> <invitemask>"
  RPL_INVITELIST=346

  # "<channel> :End of channel invite list"
  #
  # - When listing the 'invitations masks' for a given channel,
  #   a server is required to send the list back using the
  #   RPL_INVITELIST and RPL_ENDOFINVITELIST messages.  A
  #   separate RPL_INVITELIST is sent for each active mask.
  #   After the masks have been listed (or if none present) a
  #   RPL_ENDOFINVITELIST MUST be sent.
  #
  RPL_ENDOFINVITELIST=347

  # "<channel> <exceptionmask>"
  RPL_EXCEPTLIST=348

  # "<channel> :End of channel exception list"
  #
  # - When listing the 'exception masks' for a given channel,
  #   a server is required to send the list back using the
  #   RPL_EXCEPTLIST and RPL_ENDOFEXCEPTLIST messages.  A
  #   separate RPL_EXCEPTLIST is sent for each active mask.
  #   After the masks have been listed (or if none present)
  #   a RPL_ENDOFEXCEPTLIST MUST be sent.
  #
  RPL_ENDOFEXCEPTLIST=349

  # "<version>.<debuglevel> <server> :<comments>"
  #
  # - Reply by the server showing its version details.
  #
  # The <version> is the version of the software being
  # used (including any patchlevel revisions) and the
  # <debuglevel> is used to indicate if the server is
  # running in "debug mode".
  #
  # The "comments" field may contain any comments about
  # the version or further version details.
  #
  RPL_VERSION=351

  # - The RPL_WHOREPLY and RPL_ENDOFWHO pair are used
  #   to answer a WHO message.  The RPL_WHOREPLY is only
  #   sent if there is an appropriate match to the WHO
  #   query.  If there is a list of parameters supplied
  #   with a WHO message, a RPL_ENDOFWHO MUST be sent
  #   after processing each list item with <name> being
  #   the item.

  # "<channel> <user> <host> <server> <nick>
  # ( "H" / "G" > ["*"] [ ( "@" / "+" ) ]
  # :<hopcount> <real name>"
  #
  RPL_WHOREPLY=352

  # "<name> :End of WHO list"
  RPL_ENDOFWHO=315

  # - To reply to a NAMES message, a reply pair consisting
  #   of RPL_NAMREPLY and RPL_ENDOFNAMES is sent by the
  #   server back to the client.  If there is no channel
  #   found as in the query, then only RPL_ENDOFNAMES is
  #   returned.  The exception to this is when a NAMES
  #   message is sent with no parameters and all visible
  #   channels and contents are sent back in a series of
  #   RPL_NAMEREPLY messages with a RPL_ENDOFNAMES to mark
  #   the end.

  # "( "=" / "*" / "@" ) <channel>
  # :[ "@" / "+" ] <nick> *( " " [ "@" / "+" ] <nick> )
  # - "@" is used for secret channels, "*" for private
  # channels, and "=" for others (public channels).
  #
  RPL_NAMREPLY=353

  # "<channel> :End of NAMES list"
  RPL_ENDOFNAMES=366

  # - In replying to the LINKS message, a server MUST send
  #   replies back using the RPL_LINKS numeric and mark the
  #   end of the list using an RPL_ENDOFLINKS reply.

  # "<mask> <server> :<hopcount> <server info>"
  RPL_LINKS=364

  # "<mask> :End of LINKS list"
  RPL_ENDOFLINKS=365

  # - When listing the active 'bans' for a given channel,
  #   a server is required to send the list back using the
  #   RPL_BANLIST and RPL_ENDOFBANLIST messages.  A separate
  #   RPL_BANLIST is sent for each active banmask.  After the
  #   banmasks have been listed (or if none present) a
  #   RPL_ENDOFBANLIST MUST be sent.

  # "<channel> <banmask>"
  RPL_BANLIST=367

  # "<channel> :End of channel ban list"
  RPL_ENDOFBANLIST=368

  # - A server responding to an INFO message is required to
  #   send all its 'info' in a series of RPL_INFO messages
  #   with a RPL_ENDOFINFO reply to indicate the end of the
  #   replies.

  # ":<string>"
  RPL_INFO=371

  # ":End of INFO list"
  RPL_ENDOFINFO=374

  # - When responding to the MOTD message and the MOTD file
  # is found, the file is displayed line by line, with
  # each line no longer than 80 characters, using
  # RPL_MOTD format replies.  These MUST be surrounded
  # by a RPL_MOTDSTART (before the RPL_MOTDs) and an
  # RPL_ENDOFMOTD (after).

  # ":- <server> Message of the day - "
  RPL_MOTDSTART=375

  # ":- <text>"
  RPL_MOTD=372

  # ":End of MOTD command"
  RPL_ENDOFMOTD=376

  # ":You are now an IRC operator"
  #
  # - RPL_YOUREOPER is sent back to a client which has
  #   just successfully issued an OPER message and gained
  #   operator status.
  #
  RPL_YOUREOPER=381

  # "<config file> :Rehashing"
  #
  # - If the REHASH option is used and an operator sends
  #   a REHASH message, an RPL_REHASHING is sent back to
  #   the operator.
  #
  RPL_REHASHING=382

  # "You are service <servicename>"
  #
  # - Sent by the server to a service upon successful
  #   registration.
  #
  RPL_YOURESERVICE=383

  # "<server> :<string showing server's local time>"
  #
  # - When replying to the TIME message, a server MUST send
  #   the reply using the RPL_TIME format above.  The string
  #   showing the time need only contain the correct day and
  #   time there.  There is no further requirement for the
  #   time string.
  #
  RPL_TIME=391

  # - If the USERS message is handled by a server, the
  #   replies RPL_USERSTART, RPL_USERS, RPL_ENDOFUSERS and
  #   RPL_NOUSERS are used.  RPL_USERSSTART MUST be sent
  #   first, following by either a sequence of RPL_USERS
  #   or a single RPL_NOUSER.  Following this is
  #   RPL_ENDOFUSERS.

  # ":UserID   Terminal  Host"
  RPL_USERSSTART=392

  # ":<username> <ttyline> <hostname>"
  RPL_USERS=393

  # ":End of users"
  RPL_ENDOFUSERS=394

  # ":Nobody logged in"
  RPL_NOUSERS=395

  # - The RPL_TRACE* are all returned by the server in
  #   response to the TRACE message.  How many are
  #   returned is dependent on the TRACE message and
  #   whether it was sent by an operator or not.  There
  #   is no predefined order for which occurs first.
  #   Replies RPL_TRACEUNKNOWN, RPL_TRACECONNECTING and
  #   RPL_TRACEHANDSHAKE are all used for connections
  #   which have not been fully established and are either
  #   unknown, still attempting to connect or in the
  #   process of completing the 'server handshake'.
  #   RPL_TRACELINK is sent by any server which handles
  #   a TRACE message and has to pass it on to another
  #   server.  The list of RPL_TRACELINKs sent in
  #   response to a TRACE command traversing the IRC
  #   network should reflect the actual connectivity of
  #   the servers themselves along that path.
  #
  # RPL_TRACENEWTYPE is to be used for any connection
  # which does not fit in the other categories but is
  # being displayed anyway.
  # RPL_TRACEEND is sent to indicate the end of the list.

  # "Link <version & debug level> <destination>
  # <next server> V<protocol version>
  # <link uptime in seconds> <backstream sendq>
  # <upstream sendq>"
  RPL_TRACELINK=200

  # "Try. <class> <server>"
  RPL_TRACECONNECTING=201

  # "H.S. <class> <server>"
  RPL_TRACEHANDSHAKE=202

  # "???? <class> [<client IP address in dot form>]"
  RPL_TRACEUNKNOWN=203

  # "Oper <class> <nick>"
  RPL_TRACEOPERATOR=204

  # "User <class> <nick>"
  RPL_TRACEUSER=205

  # "Serv <class> <int>S <int>C <server>
  # <nick!user|*!*>@<host|server> V<protocol version>"
  RPL_TRACESERVER=206

  # "Service <class> <name> <type> <active type>"
  RPL_TRACESERVICE=207

  # "<newtype> 0 <client name>"
  RPL_TRACENEWTYPE=208

  # "Class <class> <count>"
  RPL_TRACECLASS=209

  # Unused.
  RPL_TRACERECONNECT=210

  # "File <logfile> <debug level>"
  RPL_TRACELOG=261

  # "<server name> <version & debug level> :End of TRACE"
  RPL_TRACEEND=262

  # ":Current local  users: 3  Max: 4"
  RPL_LOCALUSERS=265

  # ":Current global users: 3  Max: 4"
  RPL_GLOBALUSERS=266

  # "::Highest connection count: 4 (4 clients) (251 since server was
  # (re)started)"
  RPL_STATSCONN=250

  # "<linkname> <sendq> <sent messages>
  # <sent Kbytes> <received messages>
  # <received Kbytes> <time open>"
  #
  # - reports statistics on a connection.  <linkname>
  #   identifies the particular connection, <sendq> is
  #   the amount of data that is queued and waiting to be
  #   sent <sent messages> the number of messages sent,
  #   and <sent Kbytes> the amount of data sent, in
  #   Kbytes. <received messages> and <received Kbytes>
  #   are the equivalent of <sent messages> and <sent
  #   Kbytes> for received data, respectively.  <time
  #   open> indicates how long ago the connection was
  #   opened, in seconds.
  #
  RPL_STATSLINKINFO=211

  # "<command> <count> <byte count> <remote count>"
  #
  # - reports statistics on commands usage.
  #
  RPL_STATSCOMMANDS=212

  # "<stats letter> :End of STATS report"
  #
  RPL_ENDOFSTATS=219

  # ":Server Up %d days %d:%02d:%02d"
  #
  # - reports the server uptime.
  #
  RPL_STATSUPTIME=242

  # "O <hostmask> * <name>"
  #
  # - reports the allowed hosts from where user may become IRC
  #   operators.
  #
  RPL_STATSOLINE=243

  # "<user mode string>"
  #
  # - To answer a query about a client's own mode,
  #   RPL_UMODEIS is sent back.
  #
  RPL_UMODEIS=221

  # - When listing services in reply to a SERVLIST message,
  #   a server is required to send the list back using the
  #   RPL_SERVLIST and RPL_SERVLISTEND messages.  A separate
  #   RPL_SERVLIST is sent for each service.  After the
  #   services have been listed (or if none present) a
  #   RPL_SERVLISTEND MUST be sent.

  # "<name> <server> <mask> <type> <hopcount> <info>"
  RPL_SERVLIST=234

  # "<mask> <type> :End of service listing"
  RPL_SERVLISTEND=235

  # - In processing an LUSERS message, the server
  #   sends a set of replies from RPL_LUSERCLIENT,
  #   RPL_LUSEROP, RPL_USERUNKNOWN,
  #   RPL_LUSERCHANNELS and RPL_LUSERME.  When
  #   replying, a server MUST send back
  #   RPL_LUSERCLIENT and RPL_LUSERME.  The other
  #   replies are only sent back if a non-zero count
  #   is found for them.

  # ":There are <integer> users and <integer>
  # services on <integer> servers"
  RPL_LUSERCLIENT=251

  # "<integer> :operator(s) online"
  RPL_LUSEROP=252

  # "<integer> :unknown connection(s)"
  RPL_LUSERUNKNOWN=253

  # "<integer> :channels formed"
  RPL_LUSERCHANNELS=254

  # ":I have <integer> clients and <integer> servers"
  RPL_LUSERME=255

  # - When replying to an ADMIN message, a server
  # is expected to use replies RPL_ADMINME
  # through to RPL_ADMINEMAIL and provide a text
  # message with each.  For RPL_ADMINLOC1 a
  # description of what city, state and country
  # the server is in is expected, followed by
  # details of the institution (RPL_ADMINLOC2)
  # and finally the administrative contact for the
  # server (an email address here is REQUIRED)
  # in RPL_ADMINEMAIL.

  # "<server> :Administrative info"
  RPL_ADMINME=256

  # ":<admin info>"
  RPL_ADMINLOC1=257

  # ":<admin info>"
  RPL_ADMINLOC2=258

  # ":<admin info>"
  RPL_ADMINEMAIL=259

  # "<command> :Please wait a while and try again."
  #
  # - When a server drops a command without processing it,
  #   it MUST use the reply RPL_TRYAGAIN to inform the
  #   originating client.
  RPL_TRYAGAIN=263

  # 5.2 Error Replies
  #
  # Error replies are found in the range from 400 to 599.

  # "<nickname> :No such nick/channel"
  #
  # - Used to indicate the nickname parameter supplied to a
  #   command is currently unused.
  #
  ERR_NOSUCHNICK=401

  # "<server name> :No such server"
  #
  # - Used to indicate the server name given currently
  #   does not exist.
  #
  ERR_NOSUCHSERVER=402

  # "<channel name> :No such channel"
  #
  # - Used to indicate the given channel name is invalid.
  #
  ERR_NOSUCHCHANNEL=403

  # "<channel name> :Cannot send to channel"
  #
  # - Sent to a user who is either (a) not on a channel
  #   which is mode +n or (b) not a chanop (or mode +v) on
  #   a channel which has mode +m set or where the user is
  #   banned and is trying to send a PRIVMSG message to
  #   that channel.
  #
  ERR_CANNOTSENDTOCHAN=404

  # "<channel name> :You have joined too many channels"
  #
  # - Sent to a user when they have joined the maximum
  #   number of allowed channels and they try to join
  #   another channel.
  #
  ERR_TOOMANYCHANNELS=405

  # "<nickname> :There was no such nickname"
  #
  # - Returned by WHOWAS to indicate there is no history
  #   information for that nickname.
  #
  ERR_WASNOSUCHNICK=406

  # "<target> :<error code> recipients. <abort message>"
  #
  # - Returned to a client which is attempting to send a
  #   PRIVMSG/NOTICE using the user@host destination format
  #   and for a user@host which has several occurrences.
  #
  # - Returned to a client which trying to send a
  #   PRIVMSG/NOTICE to too many recipients.
  #
  # - Returned to a client which is attempting to JOIN a safe
  #   channel using the shortname when there are more than one
  #   such channel.
  #
  ERR_TOOMANYTARGETS=407

  # "<service name> :No such service"
  #
  # - Returned to a client which is attempting to send a SQUERY
  #   to a service which does not exist.
  #
  ERR_NOSUCHSERVICE=408

  # ":No origin specified"
  #
  # - PING or PONG message missing the originator parameter.
  #
  ERR_NOORIGIN=409

  # ":No recipient given (<command>)"
  ERR_NORECIPIENT=411

  # - 412 - 415 are returned by PRIVMSG to indicate that
  #   the message wasn't delivered for some reason.
  #   ERR_NOTOPLEVEL and ERR_WILDTOPLEVEL are errors that
  #   are returned when an invalid use of
  #   "PRIVMSG $<server>" or "PRIVMSG #<host>" is attempted.

  # ":No text to send"
  ERR_NOTEXTTOSEND=412

  # "<mask> :No toplevel domain specified"
  ERR_NOTOPLEVEL=413

  # "<mask> :Wildcard in toplevel domain"
  ERR_WILDTOPLEVEL=414

  # "<mask> :Bad Server/host mask"
  ERR_BADMASK=415

  # "<command> :Unknown command"
  #
  # - Returned to a registered client to indicate that the
  #   command sent is unknown by the server.
  #
  ERR_UNKNOWNCOMMAND=421

  # ":MOTD File is missing"
  #
  # - Server's MOTD file could not be opened by the server.
  #
  ERR_NOMOTD=422

  # "<server> :No administrative info available"
  #
  # - Returned by a server in response to an ADMIN message
  #   when there is an error in finding the appropriate
  #   information.
  #
  ERR_NOADMININFO=423

  # ":File error doing <file op> on <file>"
  #
  # - Generic error message used to report a failed file
  #   operation during the processing of a message.
  #
  ERR_FILEERROR=424

  # ":No nickname given"
  #
  # - Returned when a nickname parameter expected for a
  #   command and isn't found.
  #
  ERR_NONICKNAMEGIVEN=431

  # "<nick> :Erroneous nickname"
  #
  # - Returned after receiving a NICK message which contains
  #   characters which do not fall in the defined set.  See
  #   section 2.3.1 for details on valid nicknames.
  #
  ERR_ERRONEUSNICKNAME=432

  # "<nick> :Nickname is already in use"
  #
  # - Returned when a NICK message is processed that results
  #   in an attempt to change to a currently existing
  #   nickname.
  #
  ERR_NICKNAMEINUSE=433

  # "<nick> :Nickname collision KILL from <user>@<host>"
  #
  # - Returned by a server to a client when it detects a
  #   nickname collision (registered of a NICK that
  #   already exists by another server).
  #
  ERR_NICKCOLLISION=436

  # "<nick/channel> :Nick/channel is temporarily unavailable"
  #
  # - Returned by a server to a user trying to join a channel
  #   currently blocked by the channel delay mechanism.
  #
  # - Returned by a server to a user trying to change nickname
  #   when the desired nickname is blocked by the nick delay
  #   mechanism.
  #
  ERR_UNAVAILRESOURCE=437

  # "<nick> <channel> :They aren't on that channel"
  #
  # - Returned by the server to indicate that the target
  #   user of the command is not on the given channel.
  #
  ERR_USERNOTINCHANNEL=441

  # "<channel> :You're not on that channel"
  #
  # - Returned by the server whenever a client tries to
  #   perform a channel affecting command for which the
  #   client isn't a member.
  #
  ERR_NOTONCHANNEL=442

  # "<user> <channel> :is already on channel"
  #
  # - Returned when a client tries to invite a user to a
  #   channel they are already on.
  #
  ERR_USERONCHANNEL=443

  # "<user> :User not logged in"
  #
  # - Returned by the summon after a SUMMON command for a
  #   user was unable to be performed since they were not
  #   logged in.
  #
  ERR_NOLOGIN=444

  # ":SUMMON has been disabled"
  #
  # - Returned as a response to the SUMMON command.  MUST be
  #   returned by any server which doesn't implement it.
  #
  ERR_SUMMONDISABLED=445

  # ":USERS has been disabled"
  #
  # - Returned as a response to the USERS command.  MUST be
  #   returned by any server which does not implement it.
  #
  ERR_USERSDISABLED=446

  # ":You have not registered"
  #
  # - Returned by the server to indicate that the client
  #   MUST be registered before the server will allow it
  #   to be parsed in detail.
  #
  ERR_NOTREGISTERED=451

  # "<command> :Not enough parameters"
  #
  # - Returned by the server by numerous commands to
  #   indicate to the client that it didn't supply enough
  #   parameters.
  #
  ERR_NEEDMOREPARAMS=461

  # ":Unauthorized command (already registered)"
  #
  # - Returned by the server to any link which tries to
  #   change part of the registered details (such as
  #   password or user details from second USER message).
  #
  ERR_ALREADYREGISTRED=462

  # ":Your host isn't among the privileged"
  #
  # - Returned to a client which attempts to register with
  #   a server which does not been setup to allow
  #   connections from the host the attempted connection
  #   is tried.
  #
  ERR_NOPERMFORHOST=463

  # ":Password incorrect"
  #
  # - Returned to indicate a failed attempt at registering
  #   a connection for which a password was required and
  #   was either not given or incorrect.
  #
  ERR_PASSWDMISMATCH=464

  # ":You are banned from this server"
  #
  # - Returned after an attempt to connect and register
  #   yourself with a server which has been setup to
  #   explicitly deny connections to you.
  #
  ERR_YOUREBANNEDCREEP=465

  # - Sent by a server to a user to inform that access to the
  #   server will soon be denied.
  #
  ERR_YOUWILLBEBANNED=466

  # "<channel> :Channel key already set"
  ERR_KEYSET=467

  # "<channel> :Cannot join channel (+l)"
  ERR_CHANNELISFULL=471

  # "<char> :is unknown mode char to me for <channel>"
  ERR_UNKNOWNMODE=472

  # "<channel> :Cannot join channel (+i)"
  ERR_INVITEONLYCHAN=473

  # "<channel> :Cannot join channel (+b)"
  ERR_BANNEDFROMCHAN=474

  # "<channel> :Cannot join channel (+k)"
  ERR_BADCHANNELKEY=475

  # "<channel> :Bad Channel Mask"
  ERR_BADCHANMASK=476

  # "<channel> :Channel doesn't support modes"
  ERR_NOCHANMODES=477

  # "<channel> <char> :Channel list is full"
  #
  ERR_BANLISTFULL=478

  # ":Permission Denied- You're not an IRC operator"
  #
  # - Any command requiring operator privileges to operate
  #   MUST return this error to indicate the attempt was
  #   unsuccessful.
  #
  ERR_NOPRIVILEGES=481

  # "<channel> :You're not channel operator"
  #
  # - Any command requiring 'chanop' privileges (such as
  #   MODE messages) MUST return this error if the client
  #   making the attempt is not a chanop on the specified
  #   channel.
  #
  #
  ERR_CHANOPRIVSNEEDED=482

  # ":You can't kill a server!"
  #
  # - Any attempts to use the KILL command on a server
  #   are to be refused and this error returned directly
  #   to the client.
  #
  ERR_CANTKILLSERVER=483

  # ":Your connection is restricted!"
  #
  # - Sent by the server to a user upon connection to indicate
  #   the restricted nature of the connection (user mode "+r").
  #
  ERR_RESTRICTED=484

  # ":You're not the original channel operator"
  #
  # - Any MODE requiring "channel creator" privileges MUST
  #   return this error if the client making the attempt is not
  #   a chanop on the specified channel.
  #
  ERR_UNIQOPPRIVSNEEDED=485

  # ":No O-lines for your host"
  #
  # - If a client sends an OPER message and the server has
  #   not been configured to allow connections from the
  #   client's host as an operator, this error MUST be
  #   returned.
  #
  ERR_NOOPERHOST=491

  # ":Unknown MODE flag"
  #
  # - Returned by the server to indicate that a MODE
  #   message was sent with a nickname parameter and that
  #   the a mode flag sent was not recognized.
  #
  ERR_UMODEUNKNOWNFLAG=501

  # ":Cannot change mode for other users"
  #
  # - Error sent to any user trying to view or change the
  #   user mode for a user other than themselves.
  #
  ERR_USERSDONTMATCH=502

  # 5.3 Reserved numerics
  #
  # These numerics are not described above since they fall into one of
  # the following categories:
  #
  # 1. no longer in use;
  #
  # 2. reserved for future planned use;
  #
  # 3. in current use but are part of a non-generic 'feature' of
  #    the current IRC server.
  #
  RPL_SERVICEINFO=231
  RPL_ENDOFSERVICES=232
  RPL_SERVICE=233
  RPL_NONE=300
  RPL_WHOISCHANOP=316
  RPL_KILLDONE=361
  RPL_CLOSING=362
  RPL_CLOSEEND=363
  RPL_INFOSTART=373
  RPL_MYPORTIS=384
  RPL_STATSCLINE=213
  RPL_STATSNLINE=214
  RPL_STATSILINE=215
  RPL_STATSKLINE=216
  RPL_STATSQLINE=217
  RPL_STATSYLINE=218
  RPL_STATSVLINE=240
  RPL_STATSLLINE=241
  RPL_STATSHLINE=244
  RPL_STATSSLINE=244
  RPL_STATSPING=246
  RPL_STATSBLINE=247
  ERR_NOSERVICEHOST=492
  RPL_DATASTR=290

  # Implements RFC 2812 and prior IRC RFCs.
  #
  # Clients should register Proc{}s to handle the various server events, and
  # the Client class will handle dispatch.
  class Client

    # the Server we're connected to
    attr_reader :server
    # the User representing us on that server
    attr_reader :user

    # Create a new Client instance
    def initialize
      @server = Server.new         # The Server
      @user = @server.user("*!*@*")     # The User representing the client on this Server

      @handlers = Hash.new

      # This is used by some messages to build lists of users that
      # will be delegated when the ENDOF... message is received
      @tmpusers = []

      # Same as above, just for bans
      @tmpbans = []
    end

    # Clear the server and reset the user
    def reset
      @server.clear
      @user = @server.user("*!*@*")
    end

    # key::   server event to handle
    # value:: proc object called when event occurs
    # set a handler for a server event
    #
    # ==server events currently supported:
    #
    # TODO handle errors ERR_CHANOPRIVSNEEDED, ERR_CANNOTSENDTOCHAN
    #
    # welcome::     server welcome message on connect
    # yourhost::    your host details (on connection)
    # created::     when the server was started
    # isupport::    information about what this server supports
    # ping::        server pings you (default handler returns a pong)
    # nicktaken::   you tried to change nick to one that's in use
    # badnick::     you tried to change nick to one that's invalid
    # topic::       someone changed the topic of a channel
    # topicinfo::   on joining a channel or asking for the topic, tells you
    #               who set it and when
    # names::       server sends list of channel members when you join
    # motd::        server message of the day
    # privmsg::     privmsg, the core of IRC, a message to you from someone
    # public::      optionally instead of getting privmsg you can hook to only
    #               the public ones...
    # msg::         or only the private ones, or both
    # kick::        someone got kicked from a channel
    # part::        someone left a channel
    # quit::        someone quit IRC
    # join::        someone joined a channel
    # changetopic:: the topic of a channel changed
    # invite::      you are invited to a channel
    # nick::        someone changed their nick
    # mode::        a mode change
    # notice::      someone sends you a notice
    # unknown::     any other message not handled by the above
    def []=(key, value)
      @handlers[key] = value
    end

    # key:: event name
    # remove a handler for a server event
    def deletehandler(key)
      @handlers.delete(key)
    end

    # takes a server string, checks for PING, PRIVMSG, NOTIFY, etc, and parses
    # numeric server replies, calling the appropriate handler for each, and
    # sending it a hash containing the data from the server
    def process(serverstring)
      data = Hash.new
      data[:serverstring] = serverstring

      unless serverstring.chomp =~ /^(:(\S+)\s)?(\S+)(\s(.*))?$/
        raise "Unparseable Server Message!!!: #{serverstring.inspect}"
      end

      prefix, command, params = $2, $3, $5

      if prefix != nil
        # Most servers will send a full nick!user@host prefix for
        # messages from users. Therefore, when the prefix doesn't match this
        # syntax it's usually the server hostname.
        #
        # This is not always true, though, since some servers do not send a
        # full hostmask for user messages.
        #
        if prefix =~ /^#{Regexp::Irc::BANG_AT}$/
          data[:source] = @server.user(prefix)
        else
          if @server.hostname
            if @server.hostname != prefix
              # TODO do we want to be able to differentiate messages that are passed on to us from /other/ servers?
              debug "Origin #{prefix} for message\n\t#{serverstring.inspect}\nis neither a user hostmask nor the server hostname\nI'll pretend that it's from the server anyway"
              data[:source] = @server
            else
              data[:source] = @server
            end
          else
            @server.instance_variable_set(:@hostname, prefix)
            data[:source] = @server
          end
        end
      end

      # split parameters in an array
      argv = []
      params.scan(/(?!:)(\S+)|:(.*)/) { argv << ($1 || $2) } if params

      if command =~ /^(\d+)$/ # Numeric replies
	data[:target] = argv[0]
        # A numeric reply /should/ be directed at the client, except when we're connecting with a used nick, in which case
        # it's directed at '*'
        not_us = !([@user.nick, '*'].include?(data[:target]))
        if not_us
          warning "Server reply #{serverstring.inspect} directed at #{data[:target]} instead of client (#{@user.nick})"
        end

        num=command.to_i
        case num
        when RPL_WELCOME
          data[:message] = argv[1]
          # "Welcome to the Internet Relay Network
          # <nick>!<user>@<host>"
          if not_us
            warning "Server thinks client (#{@user.inspect}) has a different nick"
            @user.nick = data[:target]
          end
          if data[:message] =~ /([^@!\s]+)(?:!([^@!\s]+?))?@(\S+)/
            nick = $1
            user = $2
            host = $3
            warning "Welcome message nick mismatch (#{nick} vs #{data[:target]})" if nick != data[:target]
            @user.user = user if user
            @user.host = host if host
          end
          handle(:welcome, data)
        when RPL_YOURHOST
          # "Your host is <servername>, running version <ver>"
          data[:message] = argv[1]
          handle(:yourhost, data)
        when RPL_CREATED
          # "This server was created <date>"
          data[:message] = argv[1]
          handle(:created, data)
        when RPL_MYINFO
          # "<servername> <version> <available user modes>
          # <available channel modes>"
          @server.parse_my_info(params.split(' ', 2).last)
          data[:servername] = @server.hostname
          data[:version] = @server.version
          data[:usermodes] = @server.usermodes
          data[:chanmodes] = @server.chanmodes
          handle(:myinfo, data)
        when RPL_ISUPPORT
          # "PREFIX=(ov)@+ CHANTYPES=#& :are supported by this server"
          # "MODES=4 CHANLIMIT=#:20 NICKLEN=16 USERLEN=10 HOSTLEN=63
          # TOPICLEN=450 KICKLEN=450 CHANNELLEN=30 KEYLEN=23 CHANTYPES=#
          # PREFIX=(ov)@+ CASEMAPPING=ascii CAPAB IRCD=dancer :are available
          # on this server"
          #
          @server.parse_isupport(argv[1..-2].join(' '))
          handle(:isupport, data)
        when ERR_NICKNAMEINUSE
          # "* <nick> :Nickname is already in use"
          data[:nick] = argv[1]
          data[:message] = argv[2]
          handle(:nicktaken, data)
        when ERR_ERRONEUSNICKNAME
          # "* <nick> :Erroneous nickname"
          data[:nick] = argv[1]
          data[:message] = argv[2]
          handle(:badnick, data)
        when RPL_TOPIC
          data[:channel] = @server.channel(argv[1])
          data[:topic] = argv[2]
          data[:channel].topic.text = data[:topic]

          handle(:topic, data)
        when RPL_TOPIC_INFO
          data[:nick] = @server.user(argv[0])
          data[:channel] = @server.channel(argv[1])

          # This must not be an IRC::User because it might not be an actual User,
          # and we risk overwriting valid User data
          data[:source] = argv[2].to_irc_netmask(:server => @server)

          data[:time] = Time.at(argv[3].to_i)

          data[:channel].topic.set_by = data[:source]
          data[:channel].topic.set_on = data[:time]

          handle(:topicinfo, data)
        when RPL_NAMREPLY
          # "( "=" / "*" / "@" ) <channel>
          # :[ "@" / "+" ] <nick> *( " " [ "@" / "+" ] <nick> )
          # - "@" is used for secret channels, "*" for private
          # channels, and "=" for others (public channels).
          data[:channeltype] = argv[1]
          data[:channel] = chan = @server.channel(argv[2])

          users = []
          argv[3].scan(/\S+/).each { |u|
            # FIXME beware of servers that allow multiple prefixes
            if(u =~ /^([#{@server.supports[:prefix][:prefixes].join}])?(.*)$/)
              umode = $1
              user = $2
              users << [user, umode]
            end
          }

          users.each { |ar|
            u = @server.user(ar[0])
            chan.add_user(u, :silent => true)
            debug "Adding user #{u}"
            if ar[1]
              ms = @server.mode_for_prefix(ar[1].to_sym)
              debug "\twith mode #{ar[1]} (#{ms})"
              chan.mode[ms].set(u)
            end
          }
          @tmpusers += users
        when RPL_ENDOFNAMES
          data[:channel] = @server.channel(argv[1])
          data[:users] = @tmpusers
          handle(:names, data)
          @tmpusers = Array.new
        when RPL_BANLIST
          data[:channel] = @server.channel(argv[1])
          data[:mask] = argv[2]
          data[:by] = argv[3]
          data[:at] = argv[4]
          @tmpbans << data
        when RPL_ENDOFBANLIST
          data[:channel] = @server.channel(argv[1])
          data[:bans] = @tmpbans
          handle(:banlist, data)
          @tmpbans = Array.new
        when RPL_LUSERCLIENT
          # ":There are <integer> users and <integer>
          # services on <integer> servers"
          data[:message] = argv[1]
          handle(:luserclient, data)
        when RPL_LUSEROP
          # "<integer> :operator(s) online"
          data[:ops] = argv[1].to_i
          handle(:luserop, data)
        when RPL_LUSERUNKNOWN
          # "<integer> :unknown connection(s)"
          data[:unknown] = argv[1].to_i
          handle(:luserunknown, data)
        when RPL_LUSERCHANNELS
          # "<integer> :channels formed"
          data[:channels] = argv[1].to_i
          handle(:luserchannels, data)
        when RPL_LUSERME
          # ":I have <integer> clients and <integer> servers"
          data[:message] = argv[1]
          handle(:luserme, data)
        when ERR_NOMOTD
          # ":MOTD File is missing"
          data[:message] = argv[1]
          handle(:motd_missing, data)
        when RPL_LOCALUSERS
          # ":Current local  users: 3  Max: 4"
          data[:message] = argv[1]
          handle(:localusers, data)
        when RPL_GLOBALUSERS
          # ":Current global users: 3  Max: 4"
          data[:message] = argv[1]
          handle(:globalusers, data)
        when RPL_STATSCONN
          # ":Highest connection count: 4 (4 clients) (251 since server was
          # (re)started)"
          data[:message] = argv[1]
          handle(:statsconn, data)
        when RPL_MOTDSTART
          # "<nick> :- <server> Message of the Day -"
          if argv[1] =~ /^-\s+(\S+)\s/
            server = $1
          else
            warning "Server doesn't have an RFC compliant MOTD start."
          end
          @motd = ""
        when RPL_MOTD
          if(argv[1] =~ /^-\s+(.*)$/)
            @motd << $1
            @motd << "\n"
          end
        when RPL_ENDOFMOTD
          data[:motd] = @motd
          handle(:motd, data)
        when RPL_DATASTR
          data[:text] = argv[1]
          handle(:datastr, data)
        when RPL_AWAY
          data[:nick] = user = @server.user(argv[1])
          data[:message] = argv[-1]
          user.away = data[:message]
          handle(:away, data)
	when RPL_WHOREPLY
          data[:channel] = channel = @server.channel(argv[1])
          data[:user] = argv[2]
          data[:host] = argv[3]
          data[:userserver] = argv[4]
          data[:nick] = user = @server.user(argv[5])
          if argv[6] =~ /^(H|G)(\*)?(.*)?$/
            data[:away] = ($1 == 'G')
            data[:ircop] = $2
            data[:modes] = $3.scan(/./).map { |mode|
              m = @server.supports[:prefix][:prefixes].index(mode.to_sym)
              @server.supports[:prefix][:modes][m]
            } rescue []
          else
            warning "Strange WHO reply: #{serverstring.inspect}"
          end
          data[:hopcount], data[:real_name] = argv[7].split(" ", 2)

          user.user = data[:user]
          user.host = data[:host]
          user.away = data[:away] # FIXME doesn't provide the actual message
          # TODO ircop status
          # TODO userserver
          # TODO hopcount
          user.real_name = data[:real_name]

          channel.add_user(user, :silent=>true)
          data[:modes].map { |mode|
            channel.mode[mode].set(user)
          }

          handle(:who, data)
        when RPL_ENDOFWHO
          handle(:eowho, data)
        when RPL_WHOISUSER
          @whois ||= Hash.new
          @whois[:nick] = argv[1]
          @whois[:user] = argv[2]
          @whois[:host] = argv[3]
          @whois[:real_name] = argv[-1]

          user = @server.user(@whois[:nick])
          user.user = @whois[:user]
          user.host = @whois[:host]
          user.real_name = @whois[:real_name]
        when RPL_WHOISSERVER
          @whois ||= Hash.new
          @whois[:nick] = argv[1]
          @whois[:server] = argv[2]
          @whois[:server_info] = argv[-1]
          # TODO update user info
        when RPL_WHOISOPERATOR
          @whois ||= Hash.new
          @whois[:nick] = argv[1]
          @whois[:operator] = argv[-1]
          # TODO update user info
        when RPL_WHOISIDLE
          @whois ||= Hash.new
          @whois[:nick] = argv[1]
          user = @server.user(@whois[:nick])
          @whois[:idle] = argv[2].to_i
          user.idle_since = Time.now - @whois[:idle]
          if argv[-1] == 'seconds idle, signon time'
            @whois[:signon] = Time.at(argv[3].to_i)
            user.signon = @whois[:signon]
          end
        when RPL_ENDOFWHOIS
          @whois ||= Hash.new
          @whois[:nick] = argv[1]
          data[:whois] = @whois.dup
          @whois.clear
          handle(:whois, data)
        when RPL_WHOISCHANNELS
          @whois ||= Hash.new
          @whois[:nick] = argv[1]
          @whois[:channels] ||= []
          user = @server.user(@whois[:nick])
          argv[-1].split.each do |prechan|
            pfx = prechan.scan(/[#{@server.supports[:prefix][:prefixes].join}]/)
            modes = pfx.map { |p| @server.mode_for_prefix p }
            chan = prechan[pfx.length..prechan.length]

            channel = @server.channel(chan)
            channel.add_user(user, :silent => true)
            modes.map { |mode| channel.mode[mode].set(user) }

            @whois[:channels] << [chan, modes]
          end
        when RPL_CHANNELMODEIS
          parse_mode(serverstring, argv[1..-1], data)
          handle(:mode, data)
        when RPL_CREATIONTIME
          data[:channel] = @server.channel(argv[1])
          data[:time] = Time.at(argv[2].to_i)
          data[:channel].creation_time=data[:time]
          handle(:creationtime, data)
        when RPL_CHANNEL_URL
          data[:channel] = @server.channel(argv[1])
          data[:url] = argv[2]
          data[:channel].url=data[:url].dup
          handle(:channel_url, data)
        when ERR_NOSUCHNICK
          data[:target] = argv[1]
          data[:message] = argv[2]
          handle(:nosuchtarget, data)
          if user = @server.get_user(data[:target])
            @server.delete_user(user)
          end
        when ERR_NOSUCHCHANNEL
          data[:target] = argv[1]
          data[:message] = argv[2]
          handle(:nosuchtarget, data)
          if channel = @server.get_channel(data[:target])
            @server.delete_channel(channel)
          end
        else
          warning "Unknown message #{serverstring.inspect}"
          handle(:unknown, data)
        end
	return # We've processed the numeric reply
      end

      # Otherwise, the command should be a single word
      case command.to_sym
      when :PING
        data[:pingid] = argv[0]
        handle(:ping, data)
      when :PONG
        data[:pingid] = argv[0]
        handle(:pong, data)
      when :PRIVMSG
        # you can either bind to 'PRIVMSG', to get every one and
        # parse it yourself, or you can bind to 'MSG', 'PUBLIC',
        # etc and get it all nicely split up for you.

        begin
          data[:target] = @server.user_or_channel(argv[0])
        rescue
          # The previous may fail e.g. when the target is a server or something
          # like that (e.g. $<mask>). In any of these cases, we just use the
          # String as a target
          # FIXME we probably want to explicitly check for the #<mask> $<mask>
          data[:target] = argv[0]
        end
        data[:message] = argv[1]
        handle(:privmsg, data)

        # Now we split it
        if data[:target].kind_of?(Channel)
          handle(:public, data)
        else
          handle(:msg, data)
        end
      when :NOTICE
        begin
          data[:target] = @server.user_or_channel(argv[0])
        rescue
          # The previous may fail e.g. when the target is a server or something
          # like that (e.g. $<mask>). In any of these cases, we just use the
          # String as a target
          # FIXME we probably want to explicitly check for the #<mask> $<mask>
          data[:target] = argv[0]
        end
        data[:message] = argv[1]
        case data[:source]
        when User
          handle(:notice, data)
        else
          # "server notice" (not from user, noone to reply to)
          handle(:snotice, data)
        end
      when :KICK
        data[:channel] = @server.channel(argv[0])
        data[:target] = @server.user(argv[1])
        data[:message] = argv[2]

        @server.delete_user_from_channel(data[:target], data[:channel])
        if data[:target] == @user
          @server.delete_channel(data[:channel])
        end

        handle(:kick, data)
      when :PART
        data[:channel] = @server.channel(argv[0])
        data[:message] = argv[1]

        @server.delete_user_from_channel(data[:source], data[:channel])
        if data[:source] == @user
          @server.delete_channel(data[:channel])
        end

        handle(:part, data)
      when :QUIT
        data[:message] = argv[0]
        data[:was_on] = @server.channels.inject(ChannelList.new) { |list, ch|
          list << ch if ch.has_user?(data[:source])
          list
        }

        @server.delete_user(data[:source])

        handle(:quit, data)
      when :JOIN
        data[:channel] = @server.channel(argv[0])
        data[:channel].add_user(data[:source])

        handle(:join, data)
      when :TOPIC
        data[:channel] = @server.channel(argv[0])
        data[:topic] = Channel::Topic.new(argv[1], data[:source], Time.new)
        data[:channel].topic.replace(data[:topic])

        handle(:changetopic, data)
      when :INVITE
        data[:target] = @server.user(argv[0])
        data[:channel] = @server.channel(argv[1])

        handle(:invite, data)
      when :NICK
        data[:is_on] = @server.channels.inject(ChannelList.new) { |list, ch|
          list << ch if ch.has_user?(data[:source])
          list
        }

        data[:newnick] = argv[0]
        data[:oldnick] = data[:source].nick.dup
        data[:source].nick = data[:newnick]

        debug "#{data[:oldnick]} (now #{data[:newnick]}) was on #{data[:is_on].join(', ')}"

        handle(:nick, data)
      when :MODE
        parse_mode(serverstring, argv, data)
        handle(:mode, data)
      when :ERROR
        data[:message] = argv[1]
        handle(:error, data)
      else
        warning "Unknown message #{serverstring.inspect}"
        handle(:unknown, data)
      end
    end

    private

    # key::  server event name
    # data:: hash containing data about the event, passed to the proc
    # call client's proc for an event, if they set one as a handler
    def handle(key, data)
      if(@handlers.has_key?(key))
        @handlers[key].call(data)
      end
    end

    # RPL_CHANNELMODEIS
    # MODE ([+-]<modes> (<params>)*)*
    # When a MODE message is received by a server,
    # Type C will have parameters too, so we must
    # be able to consume parameters for all
    # but Type D modes
    def parse_mode(serverstring, argv, data)
      data[:target] = @server.user_or_channel(argv[0])
      data[:modestring] = argv[1..-1].join(" ")
      # data[:modes] is an array where each element
      # is an array with two elements, the first of which
      # is either :set or :reset, and the second symbol
      # is the mode letter. An optional third element
      # is present e.g. for channel modes that need
      # a parameter
      data[:modes] = []
      case data[:target]
      when User
        # User modes aren't currently handled internally,
        # but we still parse them and delegate to the client
        warning "Unhandled user mode message '#{serverstring}'"
        argv[1..-1].each { |arg|
          setting = arg[0].chr
          if "+-".include?(setting)
            setting = setting == "+" ? :set : :reset
            arg[1..-1].each_byte { |b|
              m = b.chr.intern
              data[:modes] << [setting, m]
            }
          else
            # Although typically User modes don't take an argument,
            # this is not true for all modes on all servers. Since
            # we have no knowledge of which modes take parameters
            # and which don't we just assign it to the last
            # mode. This is not going to do strange things often,
            # as usually User modes are only set one at a time
            warning "Unhandled user mode parameter #{arg} found"
            data[:modes].last << arg
          end
        }
      when Channel
        # array of indices in data[:modes] where parameters
        # are needed
        who_wants_params = []

        modes = argv[1..-1].dup
        debug modes
        getting_args = false
        while arg = modes.shift
          debug arg
          if getting_args
            # getting args for previously set modes
            idx = who_wants_params.shift
            if idx.nil?
              warning "Oops, problems parsing #{serverstring.inspect}"
              break
            end
            data[:modes][idx] << arg
            getting_args = false if who_wants_params.empty?
          else
            debug @server.supports[:chanmodes]
            setting = :set
            arg.each_byte do |c|
              m = c.chr.intern
              case m
              when :+
                setting = :set
              when :-
                setting = :reset
              else
                data[:modes] << [setting, m]
                case m
                when *@server.supports[:chanmodes][:typea]
                  who_wants_params << data[:modes].length - 1
                when *@server.supports[:chanmodes][:typeb]
                  who_wants_params << data[:modes].length - 1
                when *@server.supports[:chanmodes][:typec]
                  if setting == :set
                    who_wants_params << data[:modes].length - 1
                  end
                when *@server.supports[:chanmodes][:typed]
                  # Nothing to do
                when *@server.supports[:prefix][:modes]
                  who_wants_params << data[:modes].length - 1
                else
                  warning "Ignoring unknown mode #{m} in #{serverstring.inspect}"
                  data[:modes].pop
                end
              end
            end
            getting_args = true unless who_wants_params.empty?
          end
        end
        unless who_wants_params.empty?
          warning "Unhandled malformed modeline #{data[:modestring]} (unexpected empty arguments)"
          return
        end

        data[:modes].each { |mode|
          set, key, val = mode
          if val
            data[:target].mode[key].send(set, val)
          else
            data[:target].mode[key].send(set)
          end
        }
      else
        warning "Ignoring #{data[:modestring]} for unrecognized target #{argv[0]} (#{data[:target].inspect})"
      end
    end
  end
end
