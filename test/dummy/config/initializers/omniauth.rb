# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do |b|
  provider :github,        ENV['GITHUB_KEY'],   ENV['GITHUB_SECRET'],   scope: 'email,profile'
  provider :facebook,      ENV['FACEBOOK_KEY'], ENV['FACEBOOK_SECRET'],
    setup: lambda { |env|
      req = Rack::Request.new(env)

      # Persist request params so callback can read them later
      env['rack.session']['dta.omniauth.params'] = req.params.slice(
        'auth_origin_url',
        'omniauth_window_type',
        # include any additional permitted params you support:
        'favorite_color'
      )

      # If your code expects auth data too:
      # env['rack.session']['dta.omniauth.auth'] = ...
    }
  provider :google_oauth2, ENV['GOOGLE_KEY'],   ENV['GOOGLE_SECRET']
  provider :apple,         ENV['APPLE_CLIENT_ID'], '', { scope: 'email name', team_id: ENV['APPLE_TEAM_ID'], key_id: ENV['APPLE_KEY'], pem: ENV['APPLE_PEM'] }
  provider :developer,
           fields: [:first_name, :last_name],
           uid_field: :last_name
end
