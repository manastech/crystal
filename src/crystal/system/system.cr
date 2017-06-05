module Crystal
  # :nodoc
  module System
    # :nodoc
    module System
      # Returns the hostname
      # def.self.hostname

      # Returns the number of logical processors available to the system.
      #
      # def self.cpu_count
    end
  end
end

require "./unix/hostname"

{% if flag?(:freebsd) || flag?(:openbsd) %}
  require "./unix/sysctl_cpucount"
{% else %}
	# TODO: restrict on flag?(:unix) after crystal > 0.22.0 is released
	require "./unix/sysconf_cpucount"
{% end %}
