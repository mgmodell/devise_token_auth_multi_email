# frozen_string_literal: true

require 'devise_token_auth/rails/routes'

module DeviseTokenAuth
  class Engine < ::Rails::Engine
    isolate_namespace DeviseTokenAuth

    initializer 'devise_token_auth.url_helpers' do
      Devise.helpers << DeviseTokenAuth::Controllers::Helpers
    end
  end

  mattr_accessor :change_headers_on_each_request,
                 :max_number_of_devices,
                 :token_lifespan,
                 :token_cost,
                 :batch_request_buffer_throttle,
                 :omniauth_prefix,
                 :default_confirm_success_url,
                 :default_password_reset_url,
                 :redirect_whitelist,
                 :check_current_password_before_update,
                 :enable_standard_devise_support,
                 :remove_tokens_after_password_reset,
                 :default_callbacks,
                 :headers_names,
                 :cookie_enabled,
                 :cookie_name,
                 :cookie_attributes,
                 :bypass_sign_in,
                 :send_confirmation_email,
                 :require_client_password_reset_token,
                 :other_uid

  self.change_headers_on_each_request       = true
  self.max_number_of_devices                = 10
  self.token_lifespan                       = 2.weeks
  self.token_cost                           = 10
  self.batch_request_buffer_throttle        = 5.seconds
  self.omniauth_prefix                      = '/omniauth'
  self.default_confirm_success_url          = nil
  self.default_password_reset_url           = nil
  self.redirect_whitelist                   = nil
  self.check_current_password_before_update = false
  self.enable_standard_devise_support       = false
  self.remove_tokens_after_password_reset   = false
  self.default_callbacks                    = true
  self.headers_names                        = { 'authorization': 'Authorization',
                                                'access-token': 'access-token',
                                                'client': 'client',
                                                'expiry': 'expiry',
                                                'uid': 'uid',
                                                'token-type': 'token-type' }
  self.cookie_enabled                       = false
  self.cookie_name                          = 'auth_cookie'
  self.cookie_attributes                    = {}
  self.bypass_sign_in                       = true
  self.send_confirmation_email              = false
  self.require_client_password_reset_token  = false
  self.other_uid                            = nil

  def self.setup(&block)
    yield self

    Rails.application.config.after_initialize do
      if defined?(::OmniAuth)
        ::OmniAuth::config.path_prefix = Devise.omniauth_path_prefix = omniauth_prefix

        # Omniauth currently does not pass along omniauth.params upon failure redirect
        # see also: https://github.com/intridea/omniauth/issues/626
        OmniAuth::FailureEndpoint.class_eval do
          def redirect_to_failure
            message_key = env['omniauth.error.type']
            origin_query_param = env['omniauth.origin'] ? "&origin=#{CGI.escape(env['omniauth.origin'])}" : ''
            strategy_name_query_param = env['omniauth.error.strategy'] ? "&strategy=#{env['omniauth.error.strategy'].name}" : ''
            extra_params = env['omniauth.params'] ? "&#{env['omniauth.params'].to_query}" : ''
            new_path = "#{env['SCRIPT_NAME']}#{OmniAuth.config.path_prefix}/failure?message=#{message_key}#{origin_query_param}#{strategy_name_query_param}#{extra_params}"
            Rack::Response.new(['302 Moved'], 302, 'Location' => new_path).finish
          end
        end

        # Omniauth currently removes omniauth.params during mocked requests
        # see also: https://github.com/intridea/omniauth/pull/812
        #
        # In Rails 7.2+, follow_redirect! preserves the POST method for 307
        # redirects.  This means the router's 307 to /omniauth/:provider is
        # followed as a POST, which OmniAuth handles in mock_request_call.
        # However the session cookie written by that Rack response is not
        # reliably forwarded to the subsequent GET /omniauth/:provider/callback
        # request in integration tests, so session['omniauth.params'] is nil
        # when mock_callback_call runs.
        #
        # Fix: also encode the omniauth params as a query string in the
        # callback redirect URL (mock_request_call) so they are available in
        # request.params as a fallback (mock_callback_call).
        OmniAuth::Strategy.class_eval do
          def mock_request_call
            setup_phase
            @env['omniauth.origin'] = request.params['origin']
            @env['omniauth.origin'] = nil if env['omniauth.origin'] == ''
            omniauth_params = request.params.except('authenticity_token')
            session['omniauth.params'] = omniauth_params
            # Set env now so redirect_to_failure (failure path) and
            # mock_callback_call (success path) both have access to params.
            @env['omniauth.params'] = omniauth_params
            mocked_auth = OmniAuth.mock_auth_for(name.to_s)
            if mocked_auth.is_a?(Symbol)
              fail!(mocked_auth)
            else
              @env['omniauth.auth'] = mocked_auth
              # Encode params in the callback URL so they survive even when the
              # session cookie is not forwarded through the redirect chain.
              redirect_target = omniauth_params.any? ?
                "#{callback_url}?#{omniauth_params.to_query}" :
                callback_url
              redirect redirect_target
            end
          end

          def mock_callback_call
            setup_phase
            @env['omniauth.origin'] = session.delete('omniauth.origin')
            @env['omniauth.origin'] = nil if env['omniauth.origin'] == ''
            # Prefer the session (Rails ≤7.1) but fall back to request params
            # (Rails 7.2+ where the session cookie may not survive the redirect).
            @env['omniauth.params'] = session.delete('omniauth.params').presence ||
                                      request.params.except('authenticity_token') ||
                                      {}
            mocked_auth = OmniAuth.mock_auth_for(name.to_s)
            if mocked_auth.is_a?(Symbol)
              fail!(mocked_auth)
            else
              @env['omniauth.auth'] = mocked_auth
              OmniAuth.config.before_callback_phase.call(@env) if OmniAuth.config.before_callback_phase
              call_app!
            end
          end
        end

      end
    end
  end
end
