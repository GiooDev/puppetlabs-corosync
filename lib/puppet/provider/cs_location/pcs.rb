require 'pathname'
require Pathname.new(__FILE__).dirname.dirname.expand_path + 'pacemaker'

Puppet::Type.type(:cs_location).provide(:pcs, :parent => Puppet::Provider::Pacemaker) do
  desc 'Specific provider for a rather specific type since I currently have no plan to
        abstract corosync/pacemaker vs. keepalived.  This provider will check the state
        of current primitive locations on the system; add, delete, or adjust various
        aspects.'

  defaultfor :operatingsystem => [:fedora, :centos, :redhat]

  commands :pcs => 'pcs'

  # given an XML element containing some <expression>s, return a hash. Return an
  # empty hash if `e` is nil.
  def self.rules_to_hash(e)
    return {} if e.nil?

    hash = {}
    e.each_element do |i|
      hash[(i.attributes['name'])] = i.attributes['value']
    end

    hash
  end

  # given an XML element (a <rsc_location> from cibadmin), produce a hash
  # suitable for creating a new provider instance.
  def self.element_to_hash(e)
    hash = {
      :name       => e.attributes['id'],
      :ensure     => :present,
      :primitive  => e.attributes['rsc'],
      :node_name  => e.attributes['node'],
      :score      => e.attributes['score'],
      :provider   => self.name,
      :rule       => rules_to_hash(e.elements['rule']),
    }

    hash
  end

  def self.instances

    block_until_ready

    instances = []

    cmd = [ command(:pcs), 'cluster', 'cib' ]
    raw, status = run_pcs_command(cmd)
    doc = REXML::Document.new(raw)

    REXML::XPath.each(doc, '//rsc_location') do |e|
      instances << new(element_to_hash(e))
    end
    instances
  end

  # Create just adds our resource to the location_hash and flush will take care
  # of actually doing the work.
  def create
    @property_hash = {
      :name       => @resource[:name],
      :ensure     => :present,
      :primitive  => @resource[:primitive],
      :node_name  => @resource[:node_name],
      :score      => @resource[:score],
      :cib        => @resource[:cib],
    }
    @property_hash[:rule] = @resource[:rule] if ! @resource[:rule].nil?
  end

  # Unlike create we actually immediately delete the item.
  def destroy
    debug('Removing location')
    cmd = [ command(:pcs), 'constraint', 'resource', 'remove', @resource[:name] ]
    Puppet::Provider::Pacemaker::run_pcs_command(cmd)
    @property_hash.clear
  end

  # Getters that obtains the parameters defined in our location that have been
  # populated by prefetch or instances (depends on if your using puppet resource
  # or not).
  def primitive
    @property_hash[:primitive]
  end

  def node_name
    @property_hash[:node_name]
  end

  def score
    @property_hash[:score]
  end

  def rule
    @property_hash[:rule]
  end

  # Our setters for parameters.  Setters are used when the resource already
  # exists so we just update the current value in the location_hash and doing
  # this marks it to be flushed.
  def primitive=(should)
    @property_hash[:primitive] = should
  end

  def node_name=(should)
    @property_hash[:node_name] = should
  end

  def score=(should)
    @property_hash[:score] = should
  end

  def rule=(should)
    @property_hash[:rule] = should
  end

  # Flush is triggered on anything that has been detected as being
  # modified in the location_hash.
  # It calls several pcs commands to make the resource look like the
  # params.
  def flush
    unless @property_hash.empty?
      cmd = [ command(:pcs), 'constraint', 'location', 'add', @property_hash[:name], @property_hash[:primitive], @property_hash[:node_name], @property_hash[:score]]
      Puppet::Provider::Pacemaker::run_pcs_command(cmd)
    end
    unless @property_hash[:rule].nil?
      score_param = [] # default value: score=INFINITY
      rule_params = []
      @property_hash[:rule].each_pair do |k,v|
        if k == 'expression'
          rule_params = [ v['attribute'], v['operation'], v['value'] ]
        elsif k == 'score' or k == 'score-attribute'
          score_param = "#{k}=#{v}"
        end
      end
      cmd_rule = [ command(:pcs), 'constraint', 'location', @property_hash[:primitive], 'rule', score_param, rule_params ]
      Puppet::Provider::Pacemaker::run_pcs_command(cmd_rule)
    end
  end
end
