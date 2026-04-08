# frozen_string_literal: true

require 'test_helper'

# Tests that verify the ConfirmationsController works correctly with a
# MultiEmailUser — a model that uses :multi_email_confirmable from the
# devise-multi_email gem.
#
# With multi_email_confirmable the confirmation token is stored on the
# MultiEmailUserEmail record (not the parent model).  The confirmations
# controller calls resource_class.confirm_by_token, which the gem overrides to
# search the email records, so the standard redirect-based confirmation flow
# continues to work.
#
# These tests are ActiveRecord-only — the MultiEmailUser model and its route
# are not available in Mongoid runs.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class MultiEmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  describe 'MultiEmailUser confirmations' do
    def registration_params(email: nil)
      {
        email:                 email || Faker::Internet.unique.email,
        password:              'secret123',
        password_confirmation: 'secret123',
        confirm_success_url:   Faker::Internet.url
      }
    end

    # Parse the confirmation token out of a mailer body.
    def token_from_mail(mail)
      mail.body.match(/confirmation_token=([^&]*)[&"]/)[1]
    end

    before do
      @redirect_url = Faker::Internet.url

      # Register a new MultiEmailUser — this triggers the confirmation email.
      @email = Faker::Internet.unique.email
      post '/multi_email_auth', params: registration_params(email: @email)
      assert_equal 200, response.status, "Setup registration failed: #{response.body}"
      @user = assigns(:resource)
      @mail = ActionMailer::Base.deliveries.last
      @token = token_from_mail(@mail)
    end

    # -----------------------------------------------------------------------
    # Show (GET) — successful confirmation
    # -----------------------------------------------------------------------
    describe 'successful confirmation via token' do
      before do
        get '/multi_email_auth/confirmation',
            params: { confirmation_token: @token, redirect_url: @redirect_url }
      end

      test 'response redirects to the redirect URL' do
        assert_redirected_to(/^#{Regexp.escape(@redirect_url)}/)
      end

      test 'redirect URL includes account_confirmation_success' do
        assert response.location.include?('account_confirmation_success')
      end

      test 'user is confirmed after following the link' do
        @user.reload
        assert @user.confirmed?
      end
    end

    # -----------------------------------------------------------------------
    # Show (GET) — invalid token
    # -----------------------------------------------------------------------
    describe 'confirmation with invalid token' do
      before do
        get '/multi_email_auth/confirmation',
            params: { confirmation_token: 'invalid-token', redirect_url: @redirect_url }
      end

      test 'response redirects (to failure URL)' do
        assert_equal 302, response.status
      end

      test 'redirect URL contains account_confirmation_success=false' do
        assert response.location.include?('account_confirmation_success=false')
      end

      test 'user is not confirmed' do
        @user.reload
        refute @user.confirmed?
      end
    end

    # -----------------------------------------------------------------------
    # Create (POST) — resend confirmation email (without paranoid mode)
    # -----------------------------------------------------------------------
    describe 'resend confirmation email — success' do
      before do
        @mail_count = ActionMailer::Base.deliveries.count

        post '/multi_email_auth/confirmation',
             params: { email: @email, redirect_url: @redirect_url }
        @data = JSON.parse(response.body)
        @resent_mail = ActionMailer::Base.deliveries.last
      end

      test 'request is successful' do
        assert_equal 200, response.status
      end

      test 'a confirmation email is sent' do
        assert_equal @mail_count + 1, ActionMailer::Base.deliveries.count
      end

      test 'email is addressed to the user' do
        assert_equal @email, @resent_mail['to'].to_s
      end

      test 'response message is returned' do
        assert @data['message']
      end
    end

    # -----------------------------------------------------------------------
    # Create (POST) — resend confirmation email (with paranoid mode)
    # -----------------------------------------------------------------------
    describe 'resend confirmation email with paranoid mode — success' do
      before do
        swap Devise, paranoid: true do
          post '/multi_email_auth/confirmation',
               params: { email: @email, redirect_url: @redirect_url }
          @data = JSON.parse(response.body)
        end
      end

      test 'request is successful' do
        assert_equal 200, response.status
      end

      test 'paranoid message is returned' do
        assert_equal I18n.t('devise_token_auth.confirmations.sended_paranoid',
                            email: @email),
                     @data['message']
      end
    end

    # -----------------------------------------------------------------------
    # Create (POST) — missing email param
    # -----------------------------------------------------------------------
    describe 'resend confirmation — missing email' do
      before do
        post '/multi_email_auth/confirmation',
             params: { redirect_url: @redirect_url }
        @data = JSON.parse(response.body)
      end

      test 'request fails' do
        assert_equal 401, response.status
      end

      test 'missing email error is returned' do
        assert @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Create (POST) — unknown email (without paranoid mode)
    # -----------------------------------------------------------------------
    describe 'resend confirmation — unknown email' do
      before do
        post '/multi_email_auth/confirmation',
             params: { email: 'nobody@example.com', redirect_url: @redirect_url }
        @data = JSON.parse(response.body)
      end

      test 'request fails with 404' do
        assert_equal 404, response.status
      end

      test 'user not found error is returned' do
        assert @data['errors']
        assert_equal [I18n.t('devise_token_auth.confirmations.user_not_found',
                              email: 'nobody@example.com')],
                     @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Create (POST) — unknown email (with paranoid mode)
    # -----------------------------------------------------------------------
    describe 'resend confirmation — unknown email with paranoid mode' do
      before do
        swap Devise, paranoid: true do
          post '/multi_email_auth/confirmation',
               params: { email: 'nobody@example.com', redirect_url: @redirect_url }
          @data = JSON.parse(response.body)
        end
      end

      test 'request returns 200 to hide existence' do
        assert_equal 200, response.status
      end

      test 'paranoid message is returned' do
        assert_equal I18n.t('devise_token_auth.confirmations.sended_paranoid',
                            email: 'nobody@example.com'),
                     @data['message']
      end
    end
  end
end
