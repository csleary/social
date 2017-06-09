# frozen_string_literal: true

require 'yaml'
require 'net/http'
require 'json'
require 'twitter'
require 'em-websocket'

Key = YAML.load_file(File.join(__dir__, 'key.yml'))

def ordinal(number)
  abs_number = number.to_i.abs

  if (11..13).cover?(abs_number % 100)
    'th'
  else
    case abs_number % 10
    when 1 then 'st'
    when 2 then 'nd'
    when 3 then 'rd'
    else 'th'
    end
  end
end

def ordinalize(number)
  "#{number}#{ordinal(number)}"
end

client = Twitter::REST::Client.new do |config|
  config.consumer_key        = Key['twitter']['consumer_key']
  config.consumer_key        = Key['twitter']['consumer_key']
  config.consumer_secret     = Key['twitter']['consumer_secret']
  config.access_token        = Key['twitter']['access_token']
  config.access_token_secret = Key['twitter']['access_token_secret']
end

EM.run do
  EM::WebSocket.run(host: '0.0.0.0', port: 8081) do |ws|
    ws.onopen do
      facebook = Net::HTTP.get_response(URI('https://graph.facebook.com/v2.8/190149549210?fields=fan_count&access_token=' + Key['facebook']))
      facebook_likes = if facebook.is_a? Net::HTTPSuccess
                         JSON.parse(facebook.body)['fan_count']
                       else
                         "E#{facebook.code}"
                       end

      mailchimp = Net::HTTP.get_response(URI('https://us2.api.mailchimp.com/3.0/lists/356ce80316/?apikey=' + Key['mailchimp']))
      mailchimp_subscribers = if mailchimp.is_a? Net::HTTPSuccess
                                JSON.parse(mailchimp.body)['stats']['member_count']
                              else
                                "E#{mailchimp.code}"
                              end

      songkick_api = Net::HTTP.get_response(URI('http://api.songkick.com/api/3.0/artists/48552/calendar.json?apikey=' + Key['songkick']))
      songkick_list = []

      if songkick_api.is_a? Net::HTTPSuccess
        unless JSON.parse(songkick_api.body)['resultsPage']['totalEntries'].zero?
          songkick_event = JSON.parse(songkick_api.body)['resultsPage']['results']['event']

          songkick_event.each do |event|
            songkick_day = ordinalize(Time.parse(event['start']['date']).strftime('%e'))
            event[:date] = Time.parse(event['start']['date']).strftime("%b #{songkick_day}, %Y")

            event[:venue] = if event['type'] == 'Festival'
                              event['displayName']
                            else
                              event['venue']['displayName']
                            end

            event[:location] = if event['location']['city'].nil?
                                 'TBA. '
                               else
                                 event['location']['city'] + '. '
                               end

            event[:time] = if event['start']['time'].nil?
                             'Doors: ' + 'TBA' + '. '
                           else
                             'Doors: ' + Time.parse(event['start']['time']).strftime('%l:%M%P') + '.'
                           end

            event[:link] = event['uri']
            # Once each event is complete, add it to the array.
            songkick_list.push(event)
          end
        end
      end

      soundcloud = Net::HTTP.get_response(URI('https://api.soundcloud.com/users/ochre?consumer_key=' + Key['soundcloud']))
      if soundcloud.is_a? Net::HTTPSuccess
        soundcloud_followers = JSON.parse(soundcloud.body)['followers_count']
      else
        soundcloud_followers = "E#{soundcloud.code}"
      end

      spotify_auth_uri = URI('https://accounts.spotify.com/api/token?grant_type=client_credentials')
      spotify_auth = Net::HTTP::Post.new(spotify_auth_uri)
      spotify_auth.basic_auth(Key['spotify']['client_id'], Key['spotify']['client_secret'])
      spotify_auth['Content-Type'] = 'application/x-www-form-urlencoded'
      spotify_auth_response = Net::HTTP.start(spotify_auth_uri.hostname, spotify_auth_uri.port, use_ssl: true) do |http|
        http.request(spotify_auth)
      end

      spotify_token = JSON.parse(spotify_auth_response.body)['access_token']
      spotify_request_uri = URI('https://api.spotify.com/v1/artists/0OmHDBh5styCXDWKwz58Ts')
      spotify_request = Net::HTTP::Get.new(spotify_request_uri)
      spotify_request['Authorization'] = "Bearer #{spotify_token}"
      spotify = Net::HTTP.start(spotify_request_uri.hostname, spotify_request_uri.port, use_ssl: true) do |http|
        http.request(spotify_request)
      end

      if spotify.is_a? Net::HTTPSuccess
        spotify_followers = JSON.parse(spotify.body)['followers']['total']
      else
        spotify_followers = "E#{spotify.code}"
      end

      twitter_followers = client.user('ochremusic').followers_count

      api_data = {
        facebook: facebook_likes,
        mailchimp: mailchimp_subscribers,
        songkick: songkick_list,
        soundcloud: soundcloud_followers,
        spotify: spotify_followers,
        twitter: twitter_followers
      }

      ws.send api_data.to_json
    end
  end
end
