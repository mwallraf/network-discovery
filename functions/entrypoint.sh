## Docker entrypoint to create the crontab scheduler

#!/bin/bash

# Start the run once job.
echo "Docker container has been started"

# Setup a cron schedule
echo "0 17 * * * cd /opt/network-discovery && /bin/bash /opt/network-discovery/discover.sh discover >> /var/log/cron.log 2>&1
@weekly rm -rf /var/log/cron.log
# This extra line makes it a valid cron" > scheduler.txt

crontab scheduler.txt
crond -f


