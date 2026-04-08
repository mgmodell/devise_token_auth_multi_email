# frozen_string_literal: true

require 'test_helper'

# Tests that verify the PasswordsController works correctly with a MultiEmailUser —
# a model that uses :multi_email_authenticatable from the devise-multi_email gem.
#
# Password reset for multi-email users works via the uid column (synced with the
# primary email by the sync_uid before_save callback) so the standard password
# reset flow applies.  The reset token is sent to the user's primary email address
# via the emails association.
#
# These tests are ActiveRecord-only — the MultiEmailUser model and its route
# are not available in Mongoid runs.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class MultiEmailPasswordsControllerTest < ActionDispatch::IntegrationTest
  RESET_PASSWORD = 'NewPassword123!'

  describe 'MultiEmailUser passwords' do
    def registration_params(email: nil)
      {
        email:                 email || Faker::Internet.unique.email,
        password:              'secret123',
        password_confirmation: 'secret123',
        confirm_success_url:   Faker::Internet.url
      }
    end

    # Create a confirmed MultiEmailUser through the endpoint, confirm it, and
    # return the user record and email address used.
    def create_confirmed_user(email: nil)
      email ||= Faker::Internet.unique.email
      post '/multi_email_auth', params: registration_params(email: email)
      assert_equal 200, response.status, "Setup registration failed: #{response.body}"
      user = assigns(:resource)
      user.confirm
      [user, email]
    end

    before do
      @redirect_url = 'http://ng-token-auth.dev'
      @user, @email = create_confirmed_user
    end

    # -----------------------------------------------------------------------
    # Create — missing email
    # -----------------------------------------------------------------------
    describe 'missing email param' do
      before do
        post '/multi_email_auth/password', params: { redirect_url: @redirect_url }
        @data = JSON.parse(response.body)
      end

      test 'request fails' do
        assert_equal 401, response.status
      end

      test 'missing email error is returned' do
        assert @data['errors']
        assert_equal [I18n.t('devise_token_auth.passwords.missing_email')],
                     @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Create — missing redirect_url
    # -----------------------------------------------------------------------
    describe 'missing redirect_url param' do
      before do
        post '/multi_email_auth/password', params: { email: @email }
        @data = JSON.parse(response.body)
      end

      test 'request fails' do
        assert_equal 401, response.status
      end

      test 'missing redirect_url error is returned' do
        assert @data['errors']
        assert_equal [I18n.t('devise_token_auth.passwords.missing_redirect_url')],
                     @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Create — unknown email (without paranoid mode)
    # -----------------------------------------------------------------------
    describe 'unknown email without paranoid mode' do
      before do
        post '/multi_email_auth/password',
             params: { email: 'unknown@example.com', redirect_url: @redirect_url }
        @data = JSON.parse(response.body)
      end

      test 'request fails with 404' do
        assert_equal 404, response.status
      end

      test 'user not found error is returned' do
        assert @data['errors']
        assert_equal [I18n.t('devise_token_auth.passwords.user_not_found',
                              email: 'unknown@example.com')],
                     @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Create — unknown email (with paranoid mode)
    # -----------------------------------------------------------------------
    describe 'unknown email with paranoid mode' do
      before do
        swap Devise, paranoid: true do
          post '/multi_email_auth/password',
               params: { email: 'unknown@example.com', redirect_url: @redirect_url }
          @data = JSON.parse(response.body)
        end
      end

      test 'request returns 200 to hide existence' do
        assert_equal 200, response.status
      end

      test 'paranoid success message is returned' do
        assert_equal I18n.t('devise_token_auth.passwords.sended_paranoid'),
                     @data['message']
      end
    end

    # -----------------------------------------------------------------------
    # Create — successful password reset request
    # -----------------------------------------------------------------------
    describe 'successful password reset request' do
      before do
        @mail_count = ActionMailer::Base.deliveries.count

        post '/multi_email_auth/password',
             params: { email: @email, redirect_url: @redirect_url }
        @data = JSON.parse(response.body)
        @mail = ActionMailer::Base.deliveries.last
      end

      test 'request is successful' do
        assert_equal 200, response.status
      end

      test 'success message is returned' do
        assert_equal I18n.t('devise_token_auth.passwords.sended', email: @email),
                     @data['message']
      end

      test 'response does not include extra data' do
        assert_nil @data['data']
      end

      test 'a password reset email is sent' do
        assert_equal @mail_count + 1, ActionMailer::Base.deliveries.count
      end

      test 'email is addressed to the user' do
        assert_equal @email, @mail['to'].to_s
      end

      test 'email body includes a reset password token' do
        assert @mail.body.match(/reset_password_token=/)
      end

      test 'email body includes the redirect URL' do
        assert @mail.body.match(/redirect_url=/)
      end
    end

    # -----------------------------------------------------------------------
    # Create — successful request with paranoid mode
    # -----------------------------------------------------------------------
    describe 'successful password reset request with paranoid mode' do
      before do
        swap Devise, paranoid: true do
          post '/multi_email_auth/password',
               params: { email: @email, redirect_url: @redirect_url }
          @data = JSON.parse(response.body)
        end
      end

      test 'request returns 200' do
        assert_equal 200, response.status
      end

      test 'paranoid success message is returned' do
        assert_equal I18n.t('devise_token_auth.passwords.sended_paranoid'),
                     @data['message']
      end
    end

    # -----------------------------------------------------------------------
    # Update — successful password change via auth token
    # -----------------------------------------------------------------------
    describe 'password update via auth headers' do
      before do
        # Request the reset link so the user gets a reset token
        post '/multi_email_auth/password',
             params: { email: @email, redirect_url: @redirect_url }
        assert_equal 200, response.status, "Reset request failed: #{response.body}"

        @reset_mail   = ActionMailer::Base.deliveries.last
        @reset_token  = @reset_mail.body.match(/reset_password_token=(.*)\"/)[1]
        @redirect_url_encoded = CGI.unescape(
          @reset_mail.body.match(/redirect_url=([^&]*)&/)[1]
        )

        # Follow the edit link to obtain auth headers
        get '/multi_email_auth/password/edit',
            params: { reset_password_token: @reset_token, redirect_url: @redirect_url }

        raw_qs  = response.location.split('?')[1]
        qs      = Rack::Utils.parse_nested_query(raw_qs)

        @auth_headers = {
          'access-token' => qs['access-token'] || qs['token'],
          'client'       => qs['client'] || qs['client_id'],
          'uid'          => qs['uid'],
          'token-type'   => 'Bearer'
        }

        # Update to a new password
        put '/multi_email_auth/password',
            params: { password: RESET_PASSWORD, password_confirmation: RESET_PASSWORD },
            headers: @auth_headers
        @data = JSON.parse(response.body)
      end

      test 'password update is successful' do
        assert_equal 200, response.status
      end

      test 'success flag is true' do
        assert @data['success']
      end

      test 'user can sign in with new password' do
        post '/multi_email_auth/sign_in',
             params: { email: @email, password: RESET_PASSWORD }
        assert_equal 200, response.status
      end
    end
  end
end
