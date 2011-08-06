# affs

require 'chef/resource'
require 'chef/config'
require 'chef/log'
require 'chef/resource/directory'
require 'chef/provider'
require 'chef/provider/file'
require 'fileutils'

# utilities
module Chef::Util::Selinux
  # written against libselinux-ruby-2.0.94-2.fc13
  require 'selinux'

  # VALUE Selinux_is_selinux_enabled(VALUE self)
  def selinux_support?
    return false unless defined?(Selinux) 
    return Selinux.is_selinux_enabled == 1 ? true : false
  end

  # VALUE Selinux_lgetfilecon(VALUE self, VALUE path)
  def selinux_get_context(path)
    return nil unless selinux_support?
    filecon = Selinux.lgetfilecon(path)
    return filecon == -1 ? nil : filecon[1]
  end

  # VALUE Selinux_lsetfilecon(VALUE self, VALUE path, VALUE con)
  def selinux_set_context(path, context)
    return nil unless selinux_support?
    retval = Selinux.lsetfilecon(path, context) 
    return retval == 0 ? true : false
  end

  # VALUE Selinux_matchpathcon(VALUE self, VALUE path, VALUE mode)
  def selinux_get_default_context(path)
    return nil unless selinux_support? 
    mode = File.lstat(path).mode || mode = 0
    pathcon = Selinux.matchpathcon(path,mode)
    return pathcon == -1 ? nil : pathcon[1]
  end

end

# resources
class Chef
  class Resource
    include Chef::Util::Selinux
  end
end

class Chef
  class Provider
    include Chef::Util::Selinux
  end
end

class Chef
  class Resource
    class File < Chef::Resource
      def selinux_label(arg=nil)
        set_or_return(
          :selinux_label,
          arg,
          :kind_of => String
        )
      end
      def selinux_label=(arg=nil)
        set_or_return(
          :selinux_label,
          arg,
          :kind_of => String
        )
      end
    end
  end
end

class Chef
  class Resource
    class Directory < Chef::Resource
      def selinux_label(arg=nil)
        set_or_return(
          :selinux_label,
          arg,
          :kind_of => String
        )
      end
      def selinux_label=(arg=nil)
        set_or_return(
          :selinux_label,
          arg,
          :kind_of => String
        )
      end
    end
  end
end

# providers
class Chef
  class Provider
    class File < Chef::Provider

      def compare_selinux_label
        @current_resource.selinux_label == @new_resource.selinux_label ||
        @current_resource.selinux_label == selinux_get_default_context(@new_resource.path)
      end

      # Set selinux label in an idempotent fashion
      def set_selinux_label
        # do nothing if label in recipe is the same as the one on the filesystem
        unless compare_selinux_label
          # if label is set in the recipe, set the value.
          if @new_resource.selinux_label != nil
            selinux_set_context(@new_resource.path,@new_resource.selinux_label)
          else
            # otherwise, use default context
            selinux_set_context(@new_resource.path,selinux_get_default_context(@new_resource.path))
          end
        end
      end

      def load_current_resource
        @current_resource = Chef::Resource::File.new(@new_resource.name)
        @new_resource.path.gsub!(/\\/, "/") # for Windows
        @current_resource.path(@new_resource.path)
        if ::File.exist?(@current_resource.path) && ::File.readable?(@current_resource.path)
          cstats = ::File.stat(@current_resource.path)
          @current_resource.owner(cstats.uid)
          @current_resource.group(cstats.gid)
          @current_resource.mode(octal_mode(cstats.mode))
          @current_resource.selinux_label(selinux_get_context(@current_resource.path)) if selinux_support?
        end
        @current_resource
      end

      def action_create
        assert_enclosing_directory_exists!
        unless ::File.exists?(@new_resource.path)
          ::File.open(@new_resource.path, "w+") {|f| f.write @new_resource.content }
          @new_resource.updated_by_last_action(true)
          Chef::Log.info("#{@new_resource} created file #{@new_resource.path}")
        else
          set_content unless @new_resource.content.nil?
        end
        set_owner unless @new_resource.owner.nil?
        set_group unless @new_resource.group.nil?
        set_mode unless @new_resource.mode.nil?
        set_selinux_label if selinux_support?
      end

    end
  end
end

class Chef
  class Provider
    class Directory < Chef::Provider::File

      def load_current_resource
        @current_resource = Chef::Resource::Directory.new(@new_resource.name)
        @current_resource.path(@new_resource.path)
        if ::File.exist?(@current_resource.path) && ::File.directory?(@current_resource.path)
          cstats = ::File.stat(@current_resource.path)
          @current_resource.owner(cstats.uid)
          @current_resource.group(cstats.gid)
          @current_resource.mode("%o" % (cstats.mode & 007777))
          @current_resource.selinux_label(selinux_get_context(@current_resource.path)) if selinux_support?
        end
        @current_resource
      end

      def action_create
        unless ::File.exists?(@new_resource.path)
          if @new_resource.recursive == true
            ::FileUtils.mkdir_p(@new_resource.path)
          else
            ::Dir.mkdir(@new_resource.path)
          end
          @new_resource.updated_by_last_action(true)
          Chef::Log.info("#{@new_resource} created directory #{@new_resource.path}")
        end
        set_owner if @new_resource.owner != nil
        set_group if @new_resource.group != nil
        set_mode if @new_resource.mode != nil
        set_selinux_label if selinux_support?
      end

    end
  end
end

class Chef
  class Provider
    class Template < Chef::Provider::File

      def load_current_resource
        super
        @current_resource.checksum(checksum(@current_resource.path)) if ::File.exist?(@current_resource.path)
        @current_resource.selinux_label(selinux_get_context(@current_resource.path)) if selinux_support?
      end

      def set_all_access_controls(file)
        access_controls = Chef::FileAccessControl.new(@new_resource, file)
        access_controls.set_all
        set_selinux_label if selinux_support?
        @new_resource.updated_by_last_action(access_controls.modified?)
      end

    end
  end
end

