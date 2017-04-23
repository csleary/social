#!/usr/bin/env ruby -wKU

require 'yaml'
require 'net/http'
require 'json'
require 'twitter'
require 'em-websocket'

def ordinal(number)
  abs_number = number.to_i.abs

  if (11..13).include?(abs_number % 100)
    "th"
  else
    case abs_number % 10
    when 1; "st"
    when 2; "nd"
    when 3; "rd"
    else    "th"
    end
  end
end

def ordinalize(number)
  "#{number}#{ordinal(number)}"
end

key = YAML.load_file(File.join(__dir__, 'key.yml'))

client = Twitter::REST::Client.new do |config|
  config.consumer_key        = key['twitter']['consumer_key']
  config.consumer_secret     = key['twitter']['consumer_secret']
  config.access_token        = key['twitter']['access_token']
  config.access_token_secret = key['twitter']['access_token_secret']
end

EM.run {
  EM::WebSocket.run(:host => "0.0.0.0", :port => 8081) do |ws|
    ws.onopen { |handshake|

      spotify = Net::HTTP.get_response(URI('https://api.spotify.com/v1/artists/0OmHDBh5styCXDWKwz58Ts'))
      if spotify.kind_of? Net::HTTPSuccess
        spotify_followers = JSON.parse(spotify.body)['followers']['total']
      else
        spotify_followers = "E#{spotify.code}"
      end

      soundcloud = Net::HTTP.get_response(URI('https://api.soundcloud.com/users/ochre?consumer_key=' + key['soundcloud']))
      if soundcloud.kind_of? Net::HTTPSuccess
        soundcloud_followers = JSON.parse(soundcloud.body)['followers_count']
      else
        soundcloud_followers = "E#{soundcloud.code}"
      end

      facebook = Net::HTTP.get_response(URI('https://graph.facebook.com/v2.8/190149549210?fields=fan_count&access_token=' + key['facebook']))
      if facebook.kind_of? Net::HTTPSuccess
        facebook_likes = JSON.parse(facebook.body)['fan_count']
      else
        facebook_likes = "E#{facebook.code}"
      end

      twitter_followers = client.user('ochremusic').followers_count

      mailchimp = Net::HTTP.get_response(URI('https://us2.api.mailchimp.com/3.0/lists/356ce80316/?apikey=' + key['mailchimp']))
      if mailchimp.kind_of? Net::HTTPSuccess
        mailchimp_subscribers = JSON.parse(mailchimp.body)['stats']['member_count']
      else
        mailchimp_subscribers = "E#{mailchimp.code}"
      end

      songkick_api = Net::HTTP.get(URI('http://api.songkick.com/api/3.0/artists/48552/calendar.json?apikey=' + key['songkick']))

      songkick_list = []
      unless JSON.parse(songkick_api)['resultsPage']['totalEntries'] == 0
        songkick_event = JSON.parse(songkick_api)['resultsPage']['results']['event']
        songkick_event.each do |event|
          songkick_day = ordinalize(Time.parse(event['start']['date']).strftime("%e"))
          event[:date] = Time.parse(event['start']['date']).strftime("%b #{songkick_day}, %Y: ")
          event[:venue] = event['venue']['displayName']
          event[:location] = ", " + event['location']['city'] + ". "
          event[:time] = "Doors: " + Time.parse(event['start']['time']).strftime("%l:%M%P") + "."
          event[:link] = event['uri']
          songkick_list.push(event) # Once each event is complete, add it to the array.
        end
      end

      api_data = {
        :spotify => spotify_followers,
        :soundcloud => soundcloud_followers,
        :facebook => facebook_likes,
        :twitter => twitter_followers,
        :mailchimp => mailchimp_subscribers,
        :songkick => songkick_list
      }

      ws.send api_data.to_json
    }
  end
}
