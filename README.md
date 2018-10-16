haproxy-check
=============

This script is to check the connection status of the haproxy backend servers.
It updates the haproxy stats files to disable/enable the backend servers depend on the time-to-first-byte.

This script should run periodically with the cron job.
