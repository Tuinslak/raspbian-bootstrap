#!/bin/bash

# rename this file to "more.sh"
# Execute and add all the stuff. Be sure to check bootstrap.sh as to what should be executed as chroot
# and what shouldn't. 

echo "#!/bin/bash
# example of additional commands. I, for example, need Puppet.
# Install Puppet, via chroot (could also be defined in packages.sh):
apt-get -y install puppet
rm -f fourth-stage" > fourth-stage

chmod +x fourth-stage

# And execute it:
echo "=> executing fourth-stage."
LANG=C chroot $rootfs /fourth-stage

mkdir -p etc/puppet

echo "[main]
logdir=/var/log/puppet
vardir=/var/lib/puppet
ssldir=/var/lib/puppet/ssl
rundir=/var/run/puppet
factpath=$vardir/lib/facter
templatedir=$confdir/templates
prerun_command=/etc/puppet/etckeeper-commit-pre
postrun_command=/etc/puppet/etckeeper-commit-post
server=puppet.yeri.be" > etc/puppet/puppet.conf

echo "
# Execute Puppet.
puppet agent --waitforcert 60" >> secondboot.sh

# EOF
