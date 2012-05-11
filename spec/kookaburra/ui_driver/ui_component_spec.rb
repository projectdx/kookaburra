require 'kookaburra/ui_driver/ui_component'
require 'support/shared_examples/it_can_make_assertions'

describe Kookaburra::UIDriver::UIComponent do
  let(:configuration) { stub('Configuration', :browser => nil, :app_host => nil, :server_error_detection => nil) }
  let(:component) { Kookaburra::UIDriver::UIComponent.new(configuration) }

  describe '#respond_to?' do
    let(:component) do
      klass = Class.new(Kookaburra::UIDriver::UIComponent) do
        def foo
        end
      end
      klass.new(configuration)
    end

    it 'returns true if the UIComponent defines the specified method' do
      component.respond_to?(:foo).should == true
    end

    it 'returns true if the #browser defines the specified method' do
      browser = stub('Browser Driver', :respond_to? => true)
      component.stub!(:browser => browser)
      component.respond_to?(:a_very_unlikely_method_name).should == true
    end

    it 'returns false if neither the UIComponent nor the #browser define the specified method' do
      browser = stub('Browser Driver', :respond_to? => false)
      component.stub!(:browser => browser)
      component.respond_to?(:a_very_unlikely_method_name).should == false
    end
  end

  describe '#method_missing' do
    context 'the component says it responds to the method' do
      it 'scopes the method call within the component_locator and forwards to #browser' do
        browser = mock('Browser Driver')
        browser.should_receive(:some_browser_method) \
          .with(:arguments) \
          .and_return(:answer_from_browser)
        browser.should_receive(:within) do |scope, &block|
          scope.should == '#my_component'
          block.call(browser)
        end
        configuration.stub!(:browser => browser)
        component.stub!(:component_locator => '#my_component')
        component.some_browser_method(:arguments).should == :answer_from_browser
      end
    end

    context 'the component says it does not respond to the method' do
      it 'raises a NoMethodError' do
        component.stub!(:respond_to? => false)
        lambda { component.no_such_method } \
          .should raise_error(NoMethodError)
      end
    end
  end

  describe "#select" do
    it "scopes #browser.select within the component_locator instead of using Kernel#select" do
      browser = mock('Browser Driver')
      browser.should_receive(:select) \
        .with(:arguments) \
        .and_return(:answer_from_browser)
      browser.should_receive(:within) do |scope, &block|
        scope.should == '#my_component'
        block.call(browser)
      end
      configuration.stub!(:browser => browser)  
      component.stub!(:component_locator => '#my_component')
      component.instance_eval {
        select(:arguments).should == :answer_from_browser
      }
    end
  end

  describe '#visible?' do
    it 'returns true if the component_locator is found in the DOM and is visible' do
      browser = mock('Browser Driver')
      browser.should_receive(:has_css?) \
        .with('#my_component', :visible) \
        .and_return(true)
      configuration.stub!(:browser => browser)
      component.stub!(:component_locator => '#my_component')
      component.visible?.should == true
    end

    it 'returns false if the component_locator id not found in the DOM' do
      browser = stub('Browser Driver', :has_css? => false)
      configuration.stub!(:browser => browser)
      server_error_detection = lambda { |browser|
        false
      }
      configuration.stub!(:server_error_detection => server_error_detection)
      component.stub!(:component_locator => '#my_component')
      component.visible?.should == false
    end

    it 'raises UnexpectedResponse if the component_locator is not found and a server error is detected' do
      browser = stub('Browser Driver', :has_css? => false)
      configuration.stub!(:browser => browser)
      server_error_detection = lambda { |browser|
        true
      }
      configuration.stub!(:server_error_detection => server_error_detection)
      component.stub!(:component_locator => '#my_component')
      component.stub!(:component_locator => '#my_component')
      lambda { component.visible? } \
        .should raise_error(Kookaburra::UnexpectedResponse) { |error|
          error.status_code.should be_nil }
    end
  end

  describe '#url' do
    it 'returns the app_host + #component_path' do
      configuration.stub!(:app_host => 'http://my.example.com')
      component.stub!(:component_path => '/foo/bar')
      component.url.should == 'http://my.example.com/foo/bar'
    end
  end

  describe 'protected methods (for use by subclasses)' do
    describe '#component_path' do
      it 'must be defined by subclasses' do
        lambda { component.send(:component_path) } \
          .should raise_error(Kookaburra::ConfigurationError)
      end
    end

    describe '#component_locator' do
      it 'must be defined by subclasses' do
        lambda { component.send(:component_locator) } \
          .should raise_error(Kookaburra::ConfigurationError)
      end
    end

    it_behaves_like :it_can_make_assertions do
      let(:subject) { component }
    end
  end
end
