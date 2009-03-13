#-- vim:sw=2:et
#++

rss_type :blog do |s|
  author = s[:author] ? (s[:author] + " ") : ""
  abt = s[:category] ? "about #{s[:category]} " : ""
  line1 = "%{handle}%{date}%{author}blogged %{abt}at %{link}"
  line2 = "%{handle}%{title} - %{desc}"
  make_stream(line1, line2, s, :author => author, :abt => abt)
end

rss_type :forum do |s|
  author = s[:author] ? (s[:author] + " ") : ""
  abt = s[:category] ? "on #{s[:category]} " : ""
  line1 = "%{handle}%{date}%{author}posted %{abt}at %{link}"
  line2 = "%{handle}%{title} - %{desc}"
  make_stream(line1, line2, s, :author => author, :abt => abt)
end

rss_type :git do |s|
  author = s[:author].sub(/@\S+?\s*>/, "@...>") + " " if s[:author]
  line1 = "%{handle}%{date}%{author}committed %{title}%{at}%{link}"
  make_stream(line1, nil, s, :author => author)
end

rss_type :gmane do |s|
  line1 = "%{handle}%{date}Message %{title} sent by %{author}. %{desc}"
  make_stream(line1, nil, s)
end

rss_type :headlines do |s|
  line1 = (s[:handle].empty? ? "%{date}" : "%{handle}") << "%{title}"
  make_stream(line1, nil, s)
end

rss_type :news do |s|
  line1 = "%{handle}%{date}%{title}%{at}%{link}" % s
  line2 = "%{handle}%{date}%{desc}" % s
  make_stream(line1, line2, s)
end

rss_type :photoblog do |s|
  author = s[:author] ? (s[:author] + " ") : ""
  abt = s[:category] ? "under #{s[:category]} " : ""
  line1 = "%{handle}%{date}%{author}added an image %{abt}at %{link}"
  line2 = "%{handle}%{title} - %{desc}"
  make_stream(line1, line2, s, :author => author, :abt => abt)
end

rss_type :trac do |s|
  author = s[:author].sub(/@\S+?\s*>/, "@...>") + ": " if s[:author]
  line1 = "%{handle}%{date}%{author}%{title}%{at}%{link}"
  line2 = nil
  unless s[:item].title =~ /^(?:Changeset \[(?:[\da-f]+)\]|\(git commit\))/
    line2 = "%{handle}%{date}%{desc}"
  end
  make_stream(line1, line2, s, :author => author)
end

rss_type :wiki do |s|
  line1 = "%{handle}%{date}%{title}%{at}%{link}"
  line1 << "has been edited by %{author}. %{desc}"
  make_stream(line1, nil, s)
end

rss_type :"/." do |s|
  dept = "(from the #{s[:item].slash_department} dept) " rescue nil
  sec = " in section #{s[:item].slash_section}" rescue nil
  line1 = "%{handle}%{date}%{dept}%{title}%{at}%{link} "
  line1 << "(posted by %{author}%{sec})"
  make_stream(line1, nil, s, :dept => dept, :sec => sec)
end
