#!/bin/sh

# pass this as the user data file to the GBrowse AWS image
# in order to start up the instance in slave mode.
exec /opt/gbrowse/etc/init.d/gbrowse-slave start

