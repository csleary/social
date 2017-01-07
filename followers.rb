#!/usr/bin/env ruby -wKU

require 'yaml'
require 'net/http'
require 'json'
require 'twitter'
require 'em-websocket'
require 'gibbon'

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

gibbon = Gibbon::Request.new(api_key: key['mailchimp'])

EM.run {
  EM::WebSocket.run(:host => "0.0.0.0", :port => 8081) do |ws|
    ws.onopen { |handshake|

      spotify = Net::HTTP.get(URI('https://api.spotify.com/v1/artists/0OmHDBh5styCXDWKwz58Ts'))
      spotify_followers = JSON.parse(spotify)['followers']['total']

      soundcloud = Net::HTTP.get(URI('https://api.soundcloud.com/users/ochre?consumer_key=' + key['soundcloud']))
      soundcloud_followers = JSON.parse(soundcloud)['followers_count']

      fb = Net::HTTP.get(URI('https://graph.facebook.com/v2.8/190149549210?fields=fan_count&access_token=' + key['facebook']))
      facebook_likes = JSON.parse(fb)['fan_count']

      twitter_followers = client.user('ochremusic').followers_count

      mailchimp_subscribers = gibbon.lists(key['ochre_list']).retrieve['stats']['member_count']

      songkick_api = Net::HTTP.get(URI('http://api.songkick.com/api/3.0/artists/48552/calendar.json?apikey=' + key['songkick']))
      songkick_date = JSON.parse(songkick_api)['resultsPage']['results']['event'][0]['start']['date']
      songkick_venue = JSON.parse(songkick_api)['resultsPage']['results']['event'][0]['venue']['displayName']
      songkick_location = JSON.parse(songkick_api)['resultsPage']['results']['event'][0]['location']['city']
      songkick_time = JSON.parse(songkick_api)['resultsPage']['results']['event'][0]['start']['time']
      songkick_url = JSON.parse(songkick_api)['resultsPage']['results']['event'][0]['uri']

      songkick_day = ordinalize(Time.parse(songkick_date).strftime("%e"))

      api_data = {
        :spotify => spotify_followers,
        :soundcloud => soundcloud_followers,
        :facebook => facebook_likes,
        :twitter => twitter_followers,
        :mailchimp => mailchimp_subscribers,
        :date => Time.parse(songkick_date).strftime("%b #{songkick_day}, %Y: "),
        :venue => songkick_venue,
        :location => ", " + songkick_location + ". ",
        :time => "Doors: " + Time.parse(songkick_time).strftime("%l:%M%P") + ".",
        :link => songkick_url
      }

      ws.send api_data.to_json
    }
  end
}
