# frozen_string_literal: true

require 'net/http'
require 'json'
require 'redis'
require 'twitter'
require 'em-websocket'

redis = Redis.new

class Followers
  def facebook
    facebook = Net::HTTP.get_response(
      URI('https://graph.facebook.com/v2.8/190149549210?'\
      'fields=fan_count&access_token=' + ENV['FACEBOOK'])
    )
    if facebook.is_a? Net::HTTPSuccess
      JSON.parse(facebook.body)['fan_count']
    else
      "E#{facebook.code}"
    end
  end

  def mailchimp
    mailchimp = Net::HTTP.get_response(
      URI('https://us2.api.mailchimp.com/3.0/lists/356ce80316/?'\
      'apikey=' + ENV['MAILCHIMP'])
    )
    if mailchimp.is_a? Net::HTTPSuccess
      JSON.parse(mailchimp.body)['stats']['member_count']
    else
      "E#{mailchimp.code}"
    end
  end

  def songkick
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

    songkick_api = Net::HTTP.get_response(
      URI('http://api.songkick.com/api/3.0/artists/48552/calendar.json?'\
      'apikey=' + ENV['SONGKICK'])
    )
    songkick_list = []

    if songkick_api.is_a? Net::HTTPSuccess
      unless JSON.parse(songkick_api.body)\
      ['resultsPage']['totalEntries'].zero?
        songkick_event = JSON.parse(songkick_api.body)\
        ['resultsPage']['results']['event']

        songkick_event.each do |event|
          songkick_day = ordinalize(
            Time.parse(event['start']['date']).strftime('%e')
          )
          event[:date] = Time.parse(
            event['start']['date']
          ).strftime("%b #{songkick_day}, %Y")

          event[:venue] =
            if event['type'] == 'Festival'
              event['displayName']
            else
              event['venue']['displayName']
            end

          event[:location] =
            if event['location']['city'].nil?
              'TBA. '
            else
              event['location']['city'] + '. '
            end

          event[:time] =
            if event['start']['time'].nil?
              'Doors: ' + 'TBA' + '. '
            else
              'Doors: ' + Time.parse(
                event['start']['time']
              ).strftime('%l:%M%P') + '.'
            end

          event[:link] = event['uri']
          # Once each event is complete, add it to the array.
          songkick_list.push(event)
        end
      end
    end
  end

  def soundcloud
    soundcloud = Net::HTTP.get_response(
      URI('https://api.soundcloud.com/users/ochre?'\
        'consumer_key=' + ENV['SOUNDCLOUD'])
    )
    if soundcloud.is_a? Net::HTTPSuccess
      JSON.parse(soundcloud.body)['followers_count']
    else
      "E#{soundcloud.code}"
    end
  end

  def spotify
    spotify_auth_uri = URI('https://accounts.spotify.com/api/token?'\
      'grant_type=client_credentials')
    spotify_auth = Net::HTTP::Post.new(spotify_auth_uri)
    spotify_auth.basic_auth(
      ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET']
    )
    spotify_auth['Content-Type'] = 'application/x-www-form-urlencoded'
    spotify_auth_response =
      Net::HTTP.start(
        spotify_auth_uri.hostname,
        spotify_auth_uri.port,
        use_ssl: true
      ) do |http|
        http.request(spotify_auth)
      end

    spotify_token = JSON.parse(spotify_auth_response.body)['access_token']
    spotify_request_uri =
      URI('https://api.spotify.com/v1/artists/0OmHDBh5styCXDWKwz58Ts')
    spotify_request = Net::HTTP::Get.new(spotify_request_uri)
    spotify_request['Authorization'] = "Bearer #{spotify_token}"
    spotify = Net::HTTP.start(
      spotify_request_uri.hostname,
      spotify_request_uri.port,
      use_ssl: true
    ) do |http|
      http.request(spotify_request)
    end

    if spotify.is_a? Net::HTTPSuccess
      JSON.parse(spotify.body)['followers']['total']
    else
      "E#{spotify.code}"
    end
  end
end

client = Twitter::REST::Client.new do |config|
  config.consumer_key        = ENV['TWITTER_CONSUMER_KEY']
  config.consumer_secret     = ENV['TWITTER_CONSUMER_SECRET']
  config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
  config.access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
end

EM.run do
  EM::WebSocket.run(host: '0.0.0.0', port: 8081) do |ws|
    ws.onopen do
      followers = Followers.new
      if redis.get('facebook_key').nil?
        facebook = { service: 'facebook', likes: followers.facebook }.to_json
        redis.set 'facebook_key', facebook
        redis.expire 'facebook_key', 300
      else
        facebook = redis.get 'facebook_key'
      end
      ws.send facebook

      if redis.get('mailchimp_key').nil?
        mailchimp = {
          service: 'mailchimp',
          subscribers: followers.mailchimp
        }.to_json
        redis.set 'mailchimp_key', mailchimp
        redis.expire 'mailchimp_key', 300
      else
        mailchimp = redis.get 'mailchimp_key'
      end
      ws.send mailchimp

      if redis.get('songkick_key').nil?
        songkick = { service: 'songkick', gigs: followers.songkick }.to_json
        redis.set 'songkick_key', songkick
        redis.expire 'songkick_key', 300
      else
        songkick = redis.get 'songkick_key'
      end
      ws.send songkick

      if redis.get('soundcloud_key').nil?
        soundcloud = {
          service: 'soundcloud',
          followers: followers.soundcloud
        }.to_json
        redis.set 'soundcloud_key', soundcloud
        redis.expire 'soundcloud_key', 300
      else
        soundcloud = redis.get 'soundcloud_key'
      end
      ws.send soundcloud

      if redis.get('spotify_key').nil?
        spotify = { service: 'spotify', followers: followers.spotify }.to_json
        redis.set 'spotify_key', spotify
        redis.expire 'spotify_key', 300
      else
        spotify = redis.get 'spotify_key'
      end
      ws.send spotify

      if redis.get('twitter_key').nil?
        twitter_followers = client.user('ochremusic').followers_count
        twitter = { service: 'twitter', followers: twitter_followers }.to_json
        redis.set 'twitter_key', twitter
        redis.expire 'twitter_key', 300
      else
        twitter = redis.get 'twitter_key'
      end
      ws.send twitter

      ws.close
    end
  end
end
