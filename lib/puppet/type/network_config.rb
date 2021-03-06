Puppet::Type.newtype(:network_config) do
  @doc = "Manage non-volatile network configuration information"

  ensurable

  newparam(:name) do
    isnamevar
    desc "The name of the physical or logical network device"
  end

  newproperty(:ipaddress) do
    desc "The IP address of the network interfaces"
  end

  newproperty(:netmask) do
    desc "The subnet mask to apply to the interface"
  end

  newproperty(:method) do
    desc "The method for determining an IP address for the interface"
    newvalues(:static, :manual, :dhcp)
    defaultto :dhcp
  end

  newproperty(:family) do
    desc "The address family to use for the interface"
    newvalues(:inet, :inet6)
    defaultto :inet
  end

  newproperty(:onboot, :boolean => true) do
    desc "Whether to bring the interface up on boot"
    newvalues(:true, :false)
    defaultto :true
  end

  newparam(:reconfigure, :boolean => true) do
    desc "Reconfigure the interface after the configuration has been updated"
    newvalues(:true, :false)
    defaultto false
  end

  # Many network configurations can take arbitrary parameters, so instead of
  # trying to list every single possible property, we accept a hash of
  # properties and let providers do specific mapping of type properties to
  # on-disk state.
  newproperty(:options) do
    desc "Provider specific options to be passed to the provider"

    def is_to_s(hash = @is)
      hash.keys.sort.map {|key| "#{key} => #{hash[key]}"}.join(", ")
    end

    def should_to_s(hash = @should)
      hash.keys.sort.map {|key| "#{key} => #{hash[key]}"}.join(", ")
    end

    defaultto {}

    validate do |value|
      raise ArgumentError, "#{self.class} requires a hash for the options property" unless value.is_a? Hash
      #provider.validate
    end
  end
end
