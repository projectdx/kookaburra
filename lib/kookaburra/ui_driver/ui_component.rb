require 'kookaburra/exceptions'
require 'kookaburra/assertion'
require 'active_support/core_ext/object/try'

class Kookaburra
  class UIDriver
    # UIComponent is intended to be subclassed to represent each component of
    # your application-under-test's user interface. The purpose of the
    # UIComponent object is to abstract away the implementation details of your
    # interface when testing and allow you to concentrate on testing your
    # business requirements. For instance, a UIComponent subclass for your
    # sign-up form might have accessors for the individual fields as well as
    # methods that allow you to perform distinct operations:
    #
    # @example SignUpForm component
    #   class SignUpForm < Kookaburra::UIDriver::UIComponent
    #     def component_path
    #       '/signup'
    #     end
    #
    #     def component_locator
    #       '#sign_up_form'
    #     end
    #
    #     def email
    #       find('#user_email').value
    #     end
    #
    #     def email=(new_email)
    #       fill_in 'user_email', :with => new_email
    #     end
    #
    #     def password
    #       find('#user_password').value
    #     end
    #
    #     def password=(new_password)
    #       fill_in 'user_password', :with => new_password
    #     end
    #
    #     def password_confirmation
    #       find('#user_password_confirmation').value
    #     end
    #
    #     def password_confirmation=(new_password_confirmation)
    #       fill_in 'user_password_confirmation', :with => new_password_confirmation
    #     end
    #
    #     def submit
    #       click_button 'Sign Up'
    #     end
    #
    #     def sign_up(data = {})
    #       self.email = data[:email]
    #       self.password = data[:password]
    #       self.password_confirmation = data[:password_confirmation]
    #       submit
    #     end
    #   end
    #
    # Note that the "browser operation" methods such as `#fill_in` and
    # `#click_button` are forwarded to the {#browser} object (see
    # {#method_missing}) and are automatically scoped to the component's DOM
    # element.    
    #
    # @abstract Subclass and implement (at least) {#component_locator}. Unless
    #   you override the default implementation of {#url}, you must also
    #   override the {#component_path} method.
    class UIComponent
      include Assertion

      # New UIComponent instances are typically created for you by your
      # {Kookaburra::UIDriver} instance.
      #
      # @see Kookaburra::UIDriver.ui_component
      #
      # @param [Kookaburra::Configuration] configuration
      def initialize(configuration)
        @browser = configuration.browser
        @app_host = configuration.app_host
        @server_error_detection = configuration.server_error_detection
      end

      # If the UIComponent is sent a message it does not understand, it will
      # forward that message on to its {#browser} but wrap the call in a block
      # provided to the the browser's `#within` method. This provides convenient
      # access to the browser driver's DSL, automatically scoped to this
      # component.
      def method_missing(name, *args, &block)
        if respond_to?(name)
          browser.within(component_locator) do
            browser.send(name, *args, &block)
          end
        else
          super
        end
      end

      # Since Kernel#select is defined, we have to override it specifically here.
      def select(*args, &block)
        browser.within(component_locator) do
          browser.select(*args, &block)
        end
      end

      # @private
      # (Not really private, but YARD seemingly lacks RDoc's :nodoc tag, and the
      # semantics here don't differ from Object#respond_to?)
      def respond_to?(name)
        super || browser.respond_to?(name)
      end

      # Is the component's element found on the page and is it considered
      # "visible" by the browser driver.
      def visible?
        visible = browser.has_css?(component_locator, :visible)
        unless visible
          detect_server_error!
        end
        visible
      end

      # Returns the full URL by appending {#component_path} to the value of the
      # {Kookaburra::Configuration#app_host} from the initialized configuration.
      def url(*args)
        "#{@app_host}#{component_path(*args)}"
      end

      protected

      # The browser object from the initialized configuration
      attr_reader :browser

      # @abstract
      # @return [String] the URL path that should be loaded in order to reach this component
      # @raise [Kookaburra::ConfigurationError] raised if you haven't provided
      #   an implementation
      def component_path
        raise ConfigurationError, "You must define #{self.class.name}#component_path."
      end

      # @abstract
      # @return [String] the CSS3 selector that will find the element in the DOM
      # @raise [Kookaburra::ConfigurationError] raised if you haven't provided
      #   an implementation
      def component_locator
        raise ConfigurationError, "You must define #{self.class.name}#component_locator."
      end

      # Runs the server error detection function specified in
      # {Kookaburra::Configuration#server_error_detection}.
      #
      # It's a noop if no server error detection was specified.
      #
      # @raise [UnexpectedResponse] raised if the server error detection
      #   function returns true
      def detect_server_error!
        if @server_error_detection.try(:call, browser)
          raise UnexpectedResponse.new, "Your server error detection function detected a server error. Looks like your application is busted. :-("
        end
      end
    end
  end
end
