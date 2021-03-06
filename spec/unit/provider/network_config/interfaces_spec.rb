#!/usr/bin/env ruby -S rspec

require 'spec_helper'

def fixture_data(file)
  basedir = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'provider', 'network_config', 'interfaces_spec')
  File.read(File.join(basedir, file))
end

provider_class = Puppet::Type.type(:network_config).provider(:interfaces)

describe provider_class do
  before :each do
    @filetype = stub 'filetype'

    @provider_class = provider_class
    @provider_class.stubs(:filetype).returns @filetype

    @provider_class.initvars
  end

  describe ".parse_file" do
    it "should read the contents of the default interfaces file" do
      @filetype.expects(:read).returns("")
      @provider_class.parse_file
    end

    it "should parse out auto interfaces" do
      @filetype.expects(:read).returns(fixture_data('loopback'))
      @provider_class.parse_file["lo"][:onboot].should == :true
    end

    it "should parse out allow-hotplug interfaces" do
      @filetype.expects(:read).returns(fixture_data('single_interface_dhcp'))
      @provider_class.parse_file["eth0"][:options][:"allow-hotplug"].should be_true
    end

    it "should parse out allow-auto interfaces" do
      @filetype.expects(:read).returns(fixture_data('two_interface_dhcp'))
      @provider_class.parse_file["eth1"][:onboot].should == :true
    end

    it "should parse out iface lines" do
      @filetype.expects(:read).returns(fixture_data('single_interface_dhcp'))
      @provider_class.parse_file["eth0"].should == {:family => "inet", :method => "dhcp", :options => {:"allow-hotplug" => true}}
    end

    it "should parse out lines following iface lines" do
      @filetype.expects(:read).returns(fixture_data('single_interface_static'))
      @provider_class.parse_file["eth0"].should == {
        :family    => "inet",
        :method    => "static",
        :ipaddress => "192.168.0.2",
        :netmask   => "255.255.255.0",
        :onboot    => :true,
        :options   => {
          "broadcast" => "192.168.0.255",
          "gateway"   => "192.168.0.1",
        }
      }
    end

    it "should parse out mapping lines"
    it "should parse out lines following mapping lines"

    it "should allow for multiple pre and post up sections"

    describe "when reading an invalid interfaces" do

      it "with misplaced options should fail" do
        @filetype.expects(:read).returns("address 192.168.1.1\niface eth0 inet static\n")
        lambda do
          @provider_class.parse_file
        end.should raise_error
      end

      it "with an option without a value should fail" do
        @filetype.expects(:read).returns("iface eth0 inet manual\naddress")
        lambda do
          @provider_class.parse_file
        end.should raise_error
      end
    end
  end

  describe ".instances" do
    # This set of tests should be split out and targeted against the
    # isomorphism mixin

    it "should create a provider for each discovered interface" do
      @filetype.expects(:read).returns(fixture_data('single_interface_dhcp'))
      providers = @provider_class.instances
      providers.map(&:name).sort.should == ["eth0", "lo"]
    end

    it "should copy the interface attributes into the provider attributes" do
      @filetype.expects(:read).returns(fixture_data('single_interface_dhcp'))
      providers = @provider_class.instances
      eth0_provider = providers.find {|prov| prov.name == "eth0"}
      lo_provider   = providers.find {|prov| prov.name == "lo"}


      eth0_provider.family.should == "inet"
      eth0_provider.method.should == "dhcp"
      eth0_provider.options.should == { :"allow-hotplug" => true }

      lo_provider.family.should == "inet"
      lo_provider.method.should == "loopback"
      lo_provider.onboot.should == :true
      lo_provider.options.should be_empty
    end
  end

  describe ".prefetch" do
    # This set of tests should be split out and targeted against the
    # isomorphism mixin

    it "should match resources to providers whose names match" do

      @filetype.stubs(:read).returns(fixture_data('single_interface_dhcp'))

      lo_resource   = mock 'lo_resource'
      lo_resource.stubs(:name).returns("lo")
      eth0_resource = mock 'eth0_resource'
      eth0_resource.stubs(:name).returns("eth0")

      lo_provider = stub 'lo_provider', :name => "lo"
      eth0_provider = stub 'eth0_provider', :name => "eth0"

      @provider_class.stubs(:instances).returns [lo_provider, eth0_provider]

      lo_resource.expects(:provider=).with(lo_provider)
      eth0_resource.expects(:provider=).with(eth0_provider)
      lo_resource.expects(:provider).returns(lo_provider)
      eth0_resource.stubs(:provider).returns(eth0_provider)

      @provider_class.prefetch("eth0" => eth0_resource, "lo" => lo_resource)
    end

    it "should create a new absent provider for resources not on disk"
  end

  describe ".format_resources" do
    before :each do
      @eth0_provider = stub 'eth0_provider',
        :name            => "eth0",
        :ensure          => :present,
        :onboot          => :true,
        :family          => "inet",
        :method          => "static",
        :ipaddress       => "169.254.0.1",
        :netmask         => "255.255.0.0",
        :options         => { :"allow-hotplug" => true, }

      @lo_provider = stub 'lo_provider',
        :name            => "lo",
        :onboot          => :true,
        :"allow-hotplug" => true,
        :family          => "inet",
        :method          => "loopback",
        :ipaddress       => nil,
        :netmask         => nil,
        :options         => { :"allow-hotplug" => true, }
    end

    let(:content) { @provider_class.format_resources([@lo_provider, @eth0_provider]) }

      describe "writing the allow-hotplug section" do
      it "should allow at most one section" do
        content.select {|line| line.match(/^allow-hotplug /)}.length.should == 1
      end

      it "should have the correct interfaces appended" do
        content.find {|line| line.match(/^allow-hotplug /)}.should include("allow-hotplug eth0 lo")
      end
    end

    describe "writing iface blocks" do
      let(:content) { @provider_class.format_resources([@lo_provider, @eth0_provider]) }

      it "should produce an iface block for each interface" do
        content.select {|line| line.match(/iface eth0 inet static/)}.length.should == 1
      end

      it "should add all options following the iface block" do
        block = [
          "iface eth0 inet static",
          "address 169.254.0.1",
          "netmask 255.255.0.0",
        ].join("\n")

        content.find {|line| line.match(/iface eth0/)}.should include(block)
      end

      it "should fail if the family property is not defined" do
        @lo_provider.unstub(:family)
        @lo_provider.stubs(:family).returns nil

        lambda do
          content
        end.should raise_exception
      end

      it "should fail if the ifaces attribute does not have the method attribute" do
        @lo_provider.unstub(:method)
        @lo_provider.stubs(:method).returns nil

        lambda do
          content
        end.should raise_exception
      end
    end
  end

  describe ".flush" do
    # This set of tests should be split out and targeted against the
    # isomorphism mixin

    before do
      @filetype.stubs(:backup)
      @filetype.stubs(:write)

      @provider_class.stubs(:needs_flush).returns true
    end

    it "should add interfaces that do not exist" do
      eth0 = @provider_class.new
      eth0.expects(:ensure).returns :present

      @provider_class.expects(:format_resources).with([eth0]).returns ["yep"]
      @provider_class.flush
    end

    it "should remove interfaces that do exist whose ensure is absent" do
      eth1 = @provider_class.new
      eth1.expects(:ensure).returns :absent

      @provider_class.expects(:format_resources).with([]).returns ["yep"]
      @provider_class.flush
    end

    it "should flush interfaces that were modified" do
      @provider_class.expects(:needs_flush=).with(true)

      eth0 = @provider_class.new
      eth0.family = :inet6

      @provider_class.flush
    end

    it "should not modify unmanaged interfaces"

    it "should back up the file if changes are made" do
      @filetype.unstub(:backup)
      @filetype.expects(:backup)

      eth0 = @provider_class.new
      eth0.stubs(:ensure).returns :present

      @provider_class.expects(:format_resources).with([eth0]).returns ["yep"]
      @provider_class.flush
    end

    it "should not flush if the interfaces file is malformed"
  end
end
