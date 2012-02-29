require 'kookaburra/ui_driver/mixins/has_browser'
require 'kookaburra/ui_driver/mixins/has_strategies'
require 'kookaburra/ui_driver/mixins/has_ui_component'

module Kookaburra
  class UIDriver
    class UIComponent
      include Kookaburra::Assertion
      include HasBrowser
      include HasStrategies
      include HasUIComponent

      ##### Class macros #####
      def self.component_locator(locator)
        define_method(:component_locator) { locator }
      end

      def self.component_path(path)
        case path
        when Symbol
          alias_method :component_path, path
        else
          define_method(:component_path) { |*args| path }
        end
      end

      def self.path_id_regex(regex)
        define_method(:path_id_regex) { regex }
      end

      ##### Instance methods #####

      # Returns the CSS locator used to locate the component in the DOM
      def component_locator
        raise "You must define component_locator in subclasses of UIComponent!"
      end

      def visible!
        raise "#{self.class} not currently visible!" unless visible?
      end

      def visible?
        v= component_visible?
        no_500_error! unless v
        v
      end

      # Default implementation navigates directly to this UIComponent's
      # `#component_path`.
      #
      # @param path_args [Argument List] Any arguments added to this method are
      #        passed through to `#component_path`.
      def show(*path_args)
        unless respond_to?(:component_path)
          raise NoMethodError, "You must either set component_path or redefine the #show method in UIComponent subclasses!"
        end
        return if visible?
        visit component_path(*path_args)
      end

      def refresh
        visit component_path
      end

      def show!(opts = {})
        show opts
        visible!
      end

      def at_path?
        (Array(component_path) + Array(alternate_paths)).include?(browser.current_path)
      end

      def component_visible?
        return false if respond_to?(:component_path) && !at_path?
        browser.has_css?(component_locator)
      end

      def alternate_paths
        []
      end

      protected

      # Methods provided by `browser` that will be scoped to this UIComponent.
      #
      # These methods are defined on UIComponent and will be delegated to
      # `browser` after being wrapped with `#in_component` calls.
      SCOPED_BROWSER_METHODS = :all, :attach_file, :check, :choose, :click_button,
        :click_link, :click_link_or_button, :click_on, :field_labeled, :fill_in,
        :find, :find_button, :find_by_id, :find_field, :find_link, :first,
        :has_button?, :has_checked_field?, :has_content?, :has_css?, :has_field?,
        :has_link?, :has_no_button?, :has_no_checked_field?, :has_no_content?,
        :has_no_css?, :has_no_field?, :has_no_link?, :has_no_select?,
        :has_no_selector?, :has_no_table?, :has_no_text?,
        :has_no_unchecked_field?, :has_no_xpath?, :has_select?, :has_selector?,
        :has_table?, :has_text?, :has_unchecked_field?, :has_xpath?, :select,
        :text, :uncheck, :unselect

      SCOPED_BROWSER_METHODS.each do |method|
        define_method(method) do |*args|
          in_component { browser.send(method, *args) }
        end
      end

      def id_from_path
        browser.current_path =~ path_id_regex
        $1.present? ? $1.to_i : nil
      end

      def in_component(&blk)
        browser.within(component_locator, &blk)
      end

      # Returns the number of elements found by `#all` for the specified criteria
      def count(*args)
        all(*args).size
      end
    end
  end
end
