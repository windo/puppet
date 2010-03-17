require 'puppet'
require 'puppet/network/handler'

# Serve Puppet elements.  Useful for querying, copying, and, um, other stuff.
class Puppet::Network::Handler
  class Resource < Handler
    desc "An interface for interacting with client-based resources that can
    be used for querying or managing remote machines without using Puppet's
    central server tools.

    The ``describe`` and ``list`` methods return TransBuckets containing
    TransObject instances (``describe`` returns a single TransBucket),
    and the ``apply`` method accepts a TransBucket of TransObjects and
    applies them locally.
    "

    attr_accessor :local

    @interface = XMLRPC::Service::Interface.new("resource") { |iface|
      iface.add_method("string apply(string, string)")
      iface.add_method("string describe(string, string, array, array)")
      iface.add_method("string list(string, array, string)")
    }

    side :client

    # Apply a TransBucket as a transaction.
    def apply(bucket, format = "yaml", client = nil, clientip = nil)
      unless local?
        begin
          case format
          when "yaml"
            bucket = YAML::load(Base64.decode64(bucket))
          else
            raise Puppet::Error, "Unsupported format '#{format}'"
          end
        rescue => detail
          raise Puppet::Error, "Could not load YAML TransBucket: #{detail}"
        end
      end

      catalog = bucket.to_catalog

      # And then apply the catalog.  This way we're reusing all
      # the code in there.  It should probably just be separated out, though.
      transaction = catalog.apply

      # And then clean up
      catalog.clear(true)

      # It'd be nice to return some kind of report, but... at this point
      # we have no such facility.
      return "success"
    end

    # Describe a given object.  This returns the 'is' values for every property
    # available on the object type.
    def describe(type, name, retrieve = nil, ignore = [], format = "yaml", client = nil, clientip = nil)
      Puppet.info "Describing #{type.to_s.capitalize}[#{name}]"
      @local = true unless client
      typeklass = nil
      unless typeklass = Puppet::Type.type(type)
        raise Puppet::Error, "Puppet type #{type} is unsupported"
      end

      obj = nil

      retrieve ||= :all
      ignore ||= []

      begin
        obj = typeklass.create(:name => name, :check => retrieve)
      rescue Puppet::Error => detail
        raise Puppet::Error, "#{type}[#{name}] could not be created: #{detail}"
      end

      unless obj
        raise XMLRPC::FaultException.new(
          1, "Could not create #{type}[#{name}]"
        )
      end

      trans = obj.to_trans

      # Now get rid of any attributes they specifically don't want
      ignore.each do |st|
        trans.delete(st) if trans.include? st
      end

      # And get rid of any attributes that are nil
      trans.each do |attr, value|
        trans.delete(attr) if value.nil?
      end

      unless @local
        case format
        when "yaml"
          trans = Base64.encode64(YAML::dump(trans))
        else
          raise XMLRPC::FaultException.new(
            1, "Unavailable config format #{format}"
          )
        end
      end

      return trans
    end

    # Create a new fileserving module.
    def initialize(hash = {})
      @local = (hash[:Local])
    end

    # List all of the elements of a given type.
    def list(type, ignore = [], base = nil, format = "yaml", client = nil, clientip = nil)
      @local = true unless client
      typeklass = nil
      unless typeklass = Puppet::Type.type(type)
        raise Puppet::Error, "Puppet type #{type} is unsupported"
      end

      # They can pass in false
      ignore ||= []
      ignore = [ignore] unless ignore.is_a? Array
      bucket = Puppet::TransBucket.new
      bucket.type = typeklass.name

      typeklass.instances.each do |obj|
        next if ignore.include? obj.name

        #object = Puppet::TransObject.new(obj.name, typeklass.name)
        bucket << obj.to_trans
      end

      unless @local
        case format
        when "yaml"
          begin
          bucket = Base64.encode64(YAML::dump(bucket))
          rescue => detail
            Puppet.err detail
            raise XMLRPC::FaultException.new(
              1, detail.to_s
            )
          end
        else
          raise XMLRPC::FaultException.new(
            1, "Unavailable config format #{format}"
          )
        end
      end

      return bucket
    end

    private

    def authcheck(file, mount, client, clientip)
      unless mount.allowed?(client, clientip)
        mount.warning "#{client} cannot access #{file}"
        raise Puppet::AuthorizationError, "Cannot access #{mount}"
      end
    end

    # Deal with ignore parameters.
    def handleignore(children, path, ignore)
      ignore.each { |ignore|
        Dir.glob(File.join(path,ignore), File::FNM_DOTMATCH) { |match|
          children.delete(File.basename(match))
        }
      }
      return children
    end

    def to_s
      "resource"
    end
  end
end

