class InsultPlugin < Plugin

## insults courtesy of http://insulthost.colorado.edu/

##
# Adjectives
##
@@adj = [
"acidic",
"antique",
"contemptible",
"culturally-unsound",
"despicable",
"evil",
"fermented",
"festering",
"foul",
"fulminating",
"humid",
"impure",
"inept",
"inferior",
"industrial",
"left-over",
"low-quality",
"malodorous",
"off-color",
"penguin-molesting",
"petrified",
"pointy-nosed",
"salty",
"sausage-snorfling",
"tastless",
"tempestuous",
"tepid",
"tofu-nibbling",
"unintelligent",
"unoriginal",
"uninspiring",
"weasel-smelling",
"wretched",
"spam-sucking",
"egg-sucking",
"decayed",
"halfbaked",
"infected",
"squishy",
"porous",
"pickled",
"coughed-up",
"thick",
"vapid",
"hacked-up",
"unmuzzled",
"bawdy",
"vain",
"lumpish",
"churlish",
"fobbing",
"rank",
"craven",
"puking",
"jarring",
"fly-bitten",
"pox-marked",
"fen-sucked",
"spongy",
"droning",
"gleeking",
"warped",
"currish",
"milk-livered",
"surly",
"mammering",
"ill-borne",
"beef-witted",
"tickle-brained",
"half-faced",
"headless",
"wayward",
"rump-fed",
"onion-eyed",
"beslubbering",
"villainous",
"lewd-minded",
"cockered",
"full-gorged",
"rude-snouted",
"crook-pated",
"pribbling",
"dread-bolted",
"fool-born",
"puny",
"fawning",
"sheep-biting",
"dankish",
"goatish",
"weather-bitten",
"knotty-pated",
"malt-wormy",
"saucyspleened",
"motley-mind",
"it-fowling",
"vassal-willed",
"loggerheaded",
"clapper-clawed",
"frothy",
"ruttish",
"clouted",
"common-kissing",
"pignutted",
"folly-fallen",
"plume-plucked",
"flap-mouthed",
"swag-bellied",
"dizzy-eyed",
"gorbellied",
"weedy",
"reeky",
"measled",
"spur-galled",
"mangled",
"impertinent",
"bootless",
"toad-spotted",
"hasty-witted",
"horn-beat",
"yeasty",
"boil-brained",
"tottering",
"hedge-born",
"hugger-muggered",
"elf-skinned",
]

##
# Amounts 
##
@@amt = [
"accumulation",
"bucket",
"coagulation",
"enema-bucketful",
"gob",
"half-mouthful",
"heap",
"mass",
"mound",
"petrification",
"pile",
"puddle",
"stack",
"thimbleful",
"tongueful",
"ooze",
"quart",
"bag",
"plate",
"ass-full",
"assload",
]

##
# Objects
##
@@noun = [
"bat toenails",
"bug spit",
"cat hair",
"chicken piss",
"dog vomit",
"dung",
"fat-woman's stomach-bile",
"fish heads",
"guano",
"gunk",
"pond scum",
"rat retch",
"red dye number-9",
"Sun IPC manuals",
"waffle-house grits",
"yoo-hoo",
"dog balls",
"seagull puke",
"cat bladders",
"pus",
"urine samples",
"squirrel guts",
"snake assholes",
"snake bait",
"buzzard gizzards",
"cat-hair-balls",
"rat-farts",
"pods",
"armadillo snouts",
"entrails",
"snake snot",
"eel ooze",
"slurpee-backwash",
"toxic waste",
"Stimpy-drool",
"poopy",
"poop",
"craptacular carpet droppings",
"jizzum",
"cold sores",
"anal warts",
]
  
  def help(plugin, topic="")
    if(plugin == "insult")
      return "insult me|<person> => insult you or <person>"
    elsif(plugin == "msginsult")
      return "msginsult <nick> => insult <nick> via /msg"
    else
      return "insult module topics: msginsult, insult"
    end
  end
  def name
    "insult"
  end
  def privmsg(m)
    suffix=""
    unless(m.params)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    msgto = m.channel
    if(m.plugin =~ /^msginsult$/)
      prefix = "you are "
      if (m.params =~ /^#/)
        prefix += "all "
      end
      msgto = m.params
      suffix = " (from #{m.sourcenick})"
    elsif(m.params =~ /^me$/)
      prefix = "you are "
    else
      who = m.params
      if (who == @bot.nick)
        who = m.sourcenick
      end
      prefix = "#{who} is "
    end
    insult = generate_insult
    @bot.say msgto, prefix + insult + suffix
  end
  def generate_insult
    adj = @@adj[rand(@@adj.length)]
    adj2 = ""
    loop do
      adj2 = @@adj[rand(@@adj.length)]
      break if adj2 != adj
    end
    amt = @@amt[rand(@@amt.length)]
    noun = @@noun[rand(@@noun.length)]
    start = "a "
    start = "an " if ['a','e','i','o','u'].include?(adj[0].chr)
    "#{start}#{adj} #{amt} of #{adj2} #{noun}"
  end
end
plugin = InsultPlugin.new
plugin.register("insult")
plugin.register("msginsult")

